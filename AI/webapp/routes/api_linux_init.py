"""Linux 初始化工具 API — 受監控主機（含單項執行/參數設定/備份還原）"""
from flask import Blueprint, jsonify, request, send_file
import subprocess
import threading
import os
import re
import uuid
import json
from datetime import datetime
from services.mongo_service import get_db
from decorators import admin_required

bp = Blueprint("api_linux_init", __name__)

INSPECTION_HOME = os.environ.get("INSPECTION_HOME", "/opt/inspection")
ANSIBLE_DIR = os.path.join(INSPECTION_HOME, "ansible")
VAULT_PASS = os.path.join(INSPECTION_HOME, ".vault_pass")
REPORTS_DIR = os.path.join(INSPECTION_HOME, "data", "linux_init_reports")
PROGRESS_DIR = os.path.join(INSPECTION_HOME, "data", "linux_init_progress")
SCRIPT_PATH = os.path.join(INSPECTION_HOME, "scripts", "sysexpert.sh")

_SAFE_FILENAME = re.compile(r'^Init_Report_[\w\-\.]+_\d{8}_\d{6}\.log$')
_VALID_ITEMS = re.compile(r'^[AaBb]\d{1,2}$')
_jobs = {}


# ─── 進度解析 ───
def _parse_progress(log_path, target_hosts):
    if not os.path.isfile(log_path):
        return {"hosts": {h: "waiting" for h in target_hosts}, "phase": "啟動中"}
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        output = f.read()
    hosts_status = {h: "waiting" for h in target_hosts}
    current_task = ""
    for line in output.split("\n"):
        if line.startswith("TASK ["):
            current_task = line.split("[")[1].split("]")[0] if "[" in line else ""
        for sw in ["ok", "changed", "fatal", "FAILED", "unreachable"]:
            if line.strip().startswith(f"{sw}: ["):
                m = re.search(r'\[([^\]]+)\]', line)
                if m and m.group(1) in hosts_status:
                    hosts_status[m.group(1)] = "failed" if sw in ("fatal", "FAILED", "unreachable") else "running"
        if "PLAY RECAP" in line:
            for h in target_hosts:
                recap = re.search(rf'{re.escape(h)}\s+:\s+ok=(\d+).*?failed=(\d+)', output[output.index("PLAY RECAP"):])
                if recap:
                    hosts_status[h] = "failed" if int(recap.group(2)) > 0 else "done"
    phase = "完成" if "PLAY RECAP" in output else (current_task or "連線中")
    return {"hosts": hosts_status, "phase": phase}


def _run_async(job_id, cmd, target_hosts, log_path):
    _jobs[job_id]["status"] = "running"
    try:
        with open(log_path, "w") as log_f:
            proc = subprocess.Popen(cmd, shell=True, stdout=log_f, stderr=subprocess.STDOUT, cwd=ANSIBLE_DIR)
            _jobs[job_id]["pid"] = proc.pid
            proc.wait(timeout=300)
        _jobs[job_id]["status"] = "done" if proc.returncode == 0 else "error"
        _jobs[job_id]["returncode"] = proc.returncode
    except subprocess.TimeoutExpired:
        proc.kill()
        _jobs[job_id]["status"] = "timeout"
    except Exception as e:
        _jobs[job_id]["status"] = "error"
        _jobs[job_id]["error"] = str(e)
    finally:
        _jobs[job_id]["finished_at"] = datetime.now().strftime("%H:%M:%S")


# ─── 主機列表 ───
@bp.route("/api/linux-init/hosts", methods=["GET"])
@admin_required
def list_hosts():
    db = get_db()
    hosts = list(db.hosts.find(
        {"os_group": {"$in": ["rocky", "rhel", "debian", "centos", "ubuntu"]},
         "status": {"$ne": "disabled"}},
        {"_id": 0, "hostname": 1, "ip": 1, "os": 1, "os_group": 1}
    ).sort("hostname", 1))
    return jsonify({"success": True, "data": hosts})


# ─── 執行初始化（支援 mode / items） ───
@bp.route("/api/linux-init/run", methods=["POST"])
@admin_required
def run_init():
    for jid, j in _jobs.items():
        if j["status"] == "running":
            return jsonify({"success": False, "error": "已有任務正在執行中", "job_id": jid}), 409

    data = request.get_json(force=True) if request.is_json else {}
    target = data.get("target", "all")
    mode = data.get("mode", "--check")
    items = data.get("items", "")  # 逗號分隔: "A1,A3,B5"

    # 驗證 items
    if items:
        item_list = [i.strip() for i in items.split(",") if i.strip()]
        for i in item_list:
            if not _VALID_ITEMS.match(i):
                return jsonify({"success": False, "error": f"無效項目: {i}"}), 400
        items = ",".join(item_list)
    elif mode not in ("--auto", "--check"):
        return jsonify({"success": False, "error": "無效模式"}), 400

    # 解析主機
    db = get_db()
    if target == "all":
        all_h = list(db.hosts.find(
            {"os_group": {"$in": ["rocky", "rhel", "debian", "centos", "ubuntu"]}, "status": {"$ne": "disabled"}},
            {"hostname": 1}
        ))
        target_hosts = [h["hostname"] for h in all_h]
    else:
        hostnames = [h.strip() for h in target.split(",") if h.strip()]
        for h in hostnames:
            if not re.match(r'^[\w\.\-]+$', h):
                return jsonify({"success": False, "error": f"無效主機名: {h}"}), 400
        valid = list(db.hosts.find({"hostname": {"$in": hostnames}}, {"hostname": 1, "ip": 1}))
        valid_names = [v["hostname"] for v in valid]
        invalid = [h for h in hostnames if h not in valid_names]
        if invalid:
            return jsonify({"success": False, "error": f"找不到: {','.join(invalid)}"}), 404
        target_hosts = valid_names

    # 讀取 B 類參數設定
    config = _get_config(db)

    job_id = datetime.now().strftime("%Y%m%d%H%M%S") + "_" + uuid.uuid4().hex[:6]
    os.makedirs(PROGRESS_DIR, exist_ok=True)
    log_path = os.path.join(PROGRESS_DIR, f"{job_id}.log")

    limit_arg = f"--limit {','.join(target_hosts)}"
    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""

    # 組合 extra-vars（寫入 JSON 檔案避免 shell 轉義問題）
    extra_vars = {}
    if items:
        extra_vars["items"] = items
    else:
        extra_vars["mode"] = mode

    # 所有參數透過 sysexpert_env 字典傳入（Ansible environment）
    env_vars = {"SYSEXPERT_NOASK": "1"}
    for k, v in config.items():
        if v:
            env_vars[k.upper()] = str(v)
    extra_vars["sysexpert_env"] = env_vars

    ev_file = os.path.join(PROGRESS_DIR, f"{job_id}_vars.json")
    with open(ev_file, "w") as f:
        json.dump(extra_vars, f)

    cmd = (
        f"ansible-playbook playbooks/linux_init.yml "
        f"-i inventory/hosts.yml {limit_arg} {vault_arg} "
        f"-e @{ev_file}"
    )

    host_ip_map = {}
    for h in db.hosts.find({"hostname": {"$in": target_hosts}}, {"hostname": 1, "ip": 1}):
        host_ip_map[h["hostname"]] = h.get("ip", "")

    mode_label = items if items else ("全自動初始化" if mode == "--auto" else "現況檢查")
    _jobs[job_id] = {
        "status": "starting", "target_hosts": target_hosts, "host_ip_map": host_ip_map,
        "log_path": log_path, "mode_label": mode_label,
        "started_at": datetime.now().strftime("%H:%M:%S"), "finished_at": None, "pid": None,
    }

    t = threading.Thread(target=_run_async, args=(job_id, cmd, target_hosts, log_path))
    t.daemon = True
    t.start()

    return jsonify({
        "success": True, "job_id": job_id,
        "message": f"{mode_label} 已啟動，共 {len(target_hosts)} 台",
        "target_hosts": target_hosts,
    })


# ─── 進度查詢 ───
@bp.route("/api/linux-init/progress/<job_id>", methods=["GET"])
@admin_required
def get_progress(job_id):
    if job_id not in _jobs:
        return jsonify({"success": False, "error": "找不到此 job"}), 404
    job = _jobs[job_id]
    progress = _parse_progress(job["log_path"], job["target_hosts"])
    host_ip_map = job.get("host_ip_map", {})
    hosts_detail = []
    done_count = 0
    for h in job["target_hosts"]:
        s = progress["hosts"].get(h, "waiting")
        if s == "done": done_count += 1
        hosts_detail.append({"hostname": h, "ip": host_ip_map.get(h, ""), "status": s})
    is_finished = job["status"] in ("done", "error", "timeout")
    log_content = None
    if is_finished and os.path.isfile(job["log_path"]):
        try:
            with open(job["log_path"], "r", encoding="utf-8", errors="replace") as f:
                log_content = f.read()[-5000:]
        except Exception:
            pass
    return jsonify({
        "success": True, "job_id": job_id, "job_status": job["status"],
        "phase": progress["phase"], "total": len(job["target_hosts"]),
        "completed": done_count, "hosts": hosts_detail,
        "started_at": job["started_at"], "finished_at": job.get("finished_at"),
        "is_finished": is_finished, "log": log_content,
        "mode_label": job.get("mode_label", ""),
    })


# ─── B 類參數設定 ───
def _get_config(db=None):
    if db is None:
        db = get_db()
    doc = db.settings.find_one({"_id": "linux_init_config"})
    defaults = {
        # A 類參數
        "sysexpert_pass_max_days": "90",
        "sysexpert_pass_min_days": "1",
        "sysexpert_pass_min_len": "8",
        "sysexpert_faillock_deny": "5",
        "sysexpert_faillock_unlock": "900",
        "sysexpert_timezone": "Asia/Taipei",
        "sysexpert_sysinfra_user": "sysinfra",
        "sysexpert_sysinfra_uid": "645",
        "sysexpert_sysinfra_pass": "1qaz@WSX",
        "sysexpert_snmp_community": "exampleup",
        "sysexpert_dns1": "10.93.168.1",
        "sysexpert_dns2": "10.93.3.1",
        "sysexpert_ntp_server": "10.93.168.1",
        "sysexpert_chrony_server": "10.93.168.1",
        # B 類參數
        "sysexpert_tmout": "600",
        "sysexpert_ulimit": "65535",
        "sysexpert_tcp_fin": "30",
        "sysexpert_histsize": "10000",
        "sysexpert_tmp_days": "7",
        "sysexpert_motd": "",
        "sysexpert_disable_svcs": "avahi-daemon cups bluetooth",
        "sysexpert_audit_path": "/etc/shadow",
        "sysexpert_authpriv_log": "/var/log/secure",
    }
    if doc:
        for k in defaults:
            if k in doc:
                defaults[k] = doc[k]
    return defaults


@bp.route("/api/linux-init/config", methods=["GET"])
@admin_required
def get_config():
    return jsonify({"success": True, "data": _get_config()})


@bp.route("/api/linux-init/config", methods=["PUT"])
@admin_required
def update_config():
    data = request.get_json(force=True) if request.is_json else {}
    db = get_db()
    allowed = [k for k in _get_config(db).keys()]  # 允許所有已定義的 key
    update = {k: str(v) for k, v in data.items() if k in allowed}
    update["updated_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    db.settings.update_one({"_id": "linux_init_config"}, {"$set": update}, upsert=True)
    return jsonify({"success": True, "message": "參數已儲存"})


# ─── 備份還原 ───
@bp.route("/api/linux-init/rollback/list", methods=["POST"])
@admin_required
def rollback_list():
    """透過 Ansible 在遠端主機列出備份"""
    data = request.get_json(force=True) if request.is_json else {}
    hostname = data.get("hostname", "")
    if not hostname or not re.match(r'^[\w\.\-]+$', hostname):
        return jsonify({"success": False, "error": "需要 hostname"}), 400

    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""
    cmd = (
        f"cd {ANSIBLE_DIR} && ansible {hostname} -i inventory/hosts.yml "
        f"-m script -a '{SCRIPT_PATH} --rollback list' {vault_arg} --become"
    )
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        # 從 Ansible 輸出中提取 JSON
        output = result.stdout
        # Ansible script 模組輸出格式: hostname | SUCCESS => { ... "stdout": "..." }
        json_start = output.find("[")
        json_end = output.rfind("]") + 1
        if json_start >= 0 and json_end > json_start:
            backups = json.loads(output[json_start:json_end])
            return jsonify({"success": True, "hostname": hostname, "data": backups})
        else:
            return jsonify({"success": True, "hostname": hostname, "data": []})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@bp.route("/api/linux-init/rollback/restore", methods=["POST"])
@admin_required
def rollback_restore():
    """透過 Ansible 在遠端主機還原備份檔"""
    data = request.get_json(force=True) if request.is_json else {}
    hostname = data.get("hostname", "")
    bak_path = data.get("bak_path", "")
    orig_path = data.get("orig_path", "")

    if not all([hostname, bak_path, orig_path]):
        return jsonify({"success": False, "error": "需要 hostname, bak_path, orig_path"}), 400

    # 安全檢查
    for p in [bak_path, orig_path]:
        if ".." in p or not p.startswith("/"):
            return jsonify({"success": False, "error": f"路徑不安全: {p}"}), 400

    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""
    cmd = (
        f"cd {ANSIBLE_DIR} && ansible {hostname} -i inventory/hosts.yml "
        f"-m shell -a 'cp -p \"{bak_path}\" \"{orig_path}\"' {vault_arg} --become"
    )
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        success = result.returncode == 0
        return jsonify({
            "success": success,
            "message": f"{'還原成功' if success else '還原失敗'}: {orig_path}",
            "output": (result.stdout + result.stderr)[-500:]
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


# ─── 報告管理 ───
@bp.route("/api/linux-init/reports", methods=["GET"])
@admin_required
def list_reports():
    return jsonify({"success": True, "data": _list_reports()})


@bp.route("/api/linux-init/reports/<filename>/download", methods=["GET"])
@admin_required
def download_report(filename):
    if not _SAFE_FILENAME.match(filename):
        return jsonify({"success": False, "error": "無效檔名"}), 400
    fp = os.path.join(REPORTS_DIR, filename)
    if not os.path.isfile(fp):
        return jsonify({"success": False, "error": "不存在"}), 404
    return send_file(fp, as_attachment=True, download_name=filename)


@bp.route("/api/linux-init/reports/<filename>/preview", methods=["GET"])
@admin_required
def preview_report(filename):
    if not _SAFE_FILENAME.match(filename):
        return jsonify({"success": False, "error": "無效檔名"}), 400
    fp = os.path.join(REPORTS_DIR, filename)
    if not os.path.isfile(fp):
        return jsonify({"success": False, "error": "不存在"}), 404
    with open(fp, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    return jsonify({"success": True, "filename": filename, "content": content})


def _list_reports():
    if not os.path.isdir(REPORTS_DIR):
        return []
    reports = []
    for fname in os.listdir(REPORTS_DIR):
        if not _SAFE_FILENAME.match(fname):
            continue
        fp = os.path.join(REPORTS_DIR, fname)
        stat = os.stat(fp)
        parts = fname.replace("Init_Report_", "").replace(".log", "")
        ts = parts[-15:]
        hostname = parts[:-16]
        try:
            date_f = f"{ts[:4]}-{ts[4:6]}-{ts[6:8]} {ts[9:11]}:{ts[11:13]}:{ts[13:15]}"
        except Exception:
            date_f = ts
        reports.append({
            "filename": fname, "hostname": hostname, "date": date_f,
            "size_kb": round(stat.st_size / 1024, 1),
            "mtime": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
        })
    reports.sort(key=lambda x: x["mtime"], reverse=True)
    return reports
