"""系統安全稽核 API — 稽核專區（含即時進度 + 參數設定）"""
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

bp = Blueprint("api_security_audit", __name__)

INSPECTION_HOME = os.environ.get("INSPECTION_HOME", "/opt/inspection")
ANSIBLE_DIR = os.path.join(INSPECTION_HOME, "ansible")
VAULT_PASS = os.path.join(INSPECTION_HOME, ".vault_pass")
AUDIT_REPORTS_DIR = os.path.join(INSPECTION_HOME, "data", "security_audit_reports")
AUDIT_SCRIPT = os.path.join(INSPECTION_HOME, "scripts", "security_audit.sh")
PROGRESS_DIR = os.path.join(INSPECTION_HOME, "data", "audit_progress")

# 合法檔名 pattern: Audit_Report_<HOSTNAME>_<YYYYMMDD>.txt
_SAFE_FILENAME = re.compile(r'^Audit_(Report_)?[\w\-\.]+_\d{8}\.(txt|tar\.gz)$')

# 記憶體中的 job 狀態（輕量，不需 DB）
_jobs = {}


def _parse_ansible_progress(log_path, target_hosts):
    """解析 Ansible 輸出，計算每台主機的進度"""
    if not os.path.isfile(log_path):
        return {"hosts": {h: "waiting" for h in target_hosts}, "phase": "啟動中"}

    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        output = f.read()

    hosts_status = {h: "waiting" for h in target_hosts}
    current_task = ""

    for line in output.split("\n"):
        # TASK [任務名稱] ****
        if line.startswith("TASK ["):
            current_task = line.split("[")[1].split("]")[0] if "[" in line else ""
        # ok: [hostname] / changed: [hostname] / fatal: [hostname]
        for status_word in ["ok", "changed", "fatal", "FAILED", "unreachable"]:
            if line.strip().startswith(f"{status_word}: ["):
                match = re.search(r'\[([^\]]+)\]', line)
                if match:
                    host = match.group(1)
                    if host in hosts_status:
                        if status_word in ("fatal", "FAILED", "unreachable"):
                            hosts_status[host] = "failed"
                        else:
                            hosts_status[host] = "running"
        # PLAY RECAP — 表示全部跑完
        if "PLAY RECAP" in line:
            # 解析 recap 行: hostname : ok=6 changed=2 ...
            for h in target_hosts:
                if h in output[output.index("PLAY RECAP"):]:
                    recap_match = re.search(
                        rf'{re.escape(h)}\s+:\s+ok=(\d+).*?failed=(\d+)',
                        output[output.index("PLAY RECAP"):]
                    )
                    if recap_match:
                        failed = int(recap_match.group(2))
                        hosts_status[h] = "failed" if failed > 0 else "done"

    # 判斷整體階段
    if "PLAY RECAP" in output:
        phase = "完成"
    elif current_task:
        phase = current_task
    else:
        phase = "連線中"

    return {"hosts": hosts_status, "phase": phase}


def _run_audit_async(job_id, cmd, target_hosts, log_path):
    """背景執行 Ansible，輸出寫到 log 檔"""
    _jobs[job_id]["status"] = "running"
    try:
        with open(log_path, "w") as log_f:
            proc = subprocess.Popen(
                cmd, shell=True, stdout=log_f, stderr=subprocess.STDOUT,
                cwd=ANSIBLE_DIR
            )
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


@bp.route("/api/security-audit/hosts", methods=["GET"])
@admin_required
def list_hosts():
    """列出可執行稽核的 Linux 主機"""
    db = get_db()
    hosts = list(db.hosts.find(
        {"os_group": {"$in": ["rocky", "rhel", "debian", "centos", "ubuntu"]},
         "status": {"$ne": "disabled"}},
        {"_id": 0, "hostname": 1, "ip": 1, "os": 1, "os_group": 1}
    ).sort("hostname", 1))
    return jsonify({"success": True, "data": hosts})


@bp.route("/api/security-audit/run", methods=["POST"])
@admin_required
def run_audit():
    """觸發安全稽核（非同步執行，回傳 job_id 供輪詢進度）"""
    # 檢查是否有正在跑的 job
    for jid, j in _jobs.items():
        if j["status"] == "running":
            return jsonify({
                "success": False,
                "error": "已有稽核正在執行中，請等待完成",
                "job_id": jid
            }), 409

    target = request.json.get("target", "all") if request.is_json else "all"

    # 驗證 target
    db = get_db()
    if target == "all":
        all_hosts = list(db.hosts.find(
            {"os_group": {"$in": ["rocky", "rhel", "debian", "centos", "ubuntu"]},
             "status": {"$ne": "disabled"}},
            {"hostname": 1}
        ))
        target_hosts = [h["hostname"] for h in all_hosts]
    else:
        hostnames = [h.strip() for h in target.split(",") if h.strip()]
        for h in hostnames:
            if not re.match(r'^[\w\.\-]+$', h):
                return jsonify({"success": False, "error": f"無效的主機名稱: {h}"}), 400
        valid = list(db.hosts.find({"hostname": {"$in": hostnames}}, {"hostname": 1, "ip": 1}))
        valid_names = [v["hostname"] for v in valid]
        invalid = [h for h in hostnames if h not in valid_names]
        if invalid:
            return jsonify({"success": False, "error": f"找不到主機: {','.join(invalid)}"}), 404
        target_hosts = valid_names
        target = ",".join(valid_names)

    # 讀取稽核參數設定
    config = _get_audit_config(db)

    # 建立 job
    job_id = datetime.now().strftime("%Y%m%d%H%M%S") + "_" + uuid.uuid4().hex[:6]
    os.makedirs(PROGRESS_DIR, exist_ok=True)
    log_path = os.path.join(PROGRESS_DIR, f"{job_id}.log")

    # 組合 extra-vars（寫入 JSON 檔避免 shell 轉義問題）
    env_vars = {}
    for k, v in config.items():
        env_vars[k.upper()] = str(v)

    ev_file = os.path.join(PROGRESS_DIR, f"{job_id}_vars.json")
    with open(ev_file, "w") as f:
        json.dump({"audit_env": env_vars}, f)

    limit_arg = f"--limit {','.join(target_hosts)}"
    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""
    cmd = (
        f"ansible-playbook playbooks/security_audit.yml "
        f"-i inventory/hosts.yml {limit_arg} {vault_arg} "
        f"-e @{ev_file}"
    )

    # 查 hostname → IP 對應
    host_ip_map = {}
    for h in db.hosts.find({"hostname": {"$in": target_hosts}}, {"hostname": 1, "ip": 1}):
        host_ip_map[h["hostname"]] = h.get("ip", "")

    _jobs[job_id] = {
        "status": "starting",
        "target_hosts": target_hosts,
        "host_ip_map": host_ip_map,
        "log_path": log_path,
        "started_at": datetime.now().strftime("%H:%M:%S"),
        "finished_at": None,
        "pid": None,
    }

    # 啟動背景 thread
    t = threading.Thread(target=_run_audit_async, args=(job_id, cmd, target_hosts, log_path))
    t.daemon = True
    t.start()

    return jsonify({
        "success": True,
        "job_id": job_id,
        "message": f"稽核已啟動，共 {len(target_hosts)} 台主機",
        "target_hosts": target_hosts
    })


@bp.route("/api/security-audit/progress/<job_id>", methods=["GET"])
@admin_required
def get_progress(job_id):
    """查詢稽核進度"""
    if job_id not in _jobs:
        return jsonify({"success": False, "error": "找不到此 job"}), 404

    job = _jobs[job_id]
    log_path = job["log_path"]
    target_hosts = job["target_hosts"]
    host_ip_map = job.get("host_ip_map", {})

    # 解析 Ansible 輸出取得每台主機狀態
    progress = _parse_ansible_progress(log_path, target_hosts)

    # 組裝結果
    hosts_detail = []
    done_count = 0
    for h in target_hosts:
        status = progress["hosts"].get(h, "waiting")
        if status == "done":
            done_count += 1
        hosts_detail.append({
            "hostname": h,
            "ip": host_ip_map.get(h, ""),
            "status": status  # waiting / running / done / failed
        })

    is_finished = job["status"] in ("done", "error", "timeout")

    # 讀取 log 內容（完成或失敗時回傳，供前端顯示）
    log_content = None
    if is_finished and os.path.isfile(log_path):
        try:
            with open(log_path, "r", encoding="utf-8", errors="replace") as f:
                log_content = f.read()[-5000:]  # 最後 5000 字元
        except Exception:
            pass

    return jsonify({
        "success": True,
        "job_id": job_id,
        "job_status": job["status"],       # starting / running / done / error / timeout
        "phase": progress["phase"],         # 當前 Ansible task 名稱
        "total": len(target_hosts),
        "completed": done_count,
        "hosts": hosts_detail,
        "started_at": job["started_at"],
        "finished_at": job.get("finished_at"),
        "is_finished": is_finished,
        "log": log_content,
    })


@bp.route("/api/security-audit/reports", methods=["GET"])
@admin_required
def list_reports():
    """列出所有稽核報告"""
    reports = _list_reports()
    return jsonify({"success": True, "data": reports})


@bp.route("/api/security-audit/reports/<filename>/download", methods=["GET"])
@admin_required
def download_report(filename):
    """下載稽核報告"""
    if not _SAFE_FILENAME.match(filename):
        return jsonify({"success": False, "error": "無效的檔案名稱"}), 400

    filepath = os.path.join(AUDIT_REPORTS_DIR, filename)
    if not os.path.isfile(filepath):
        return jsonify({"success": False, "error": "報告不存在"}), 404

    return send_file(filepath, as_attachment=True, download_name=filename)


@bp.route("/api/security-audit/reports/<filename>/preview", methods=["GET"])
@admin_required
def preview_report(filename):
    """預覽稽核報告內容"""
    if not _SAFE_FILENAME.match(filename):
        return jsonify({"success": False, "error": "無效的檔案名稱"}), 400

    filepath = os.path.join(AUDIT_REPORTS_DIR, filename)
    if not os.path.isfile(filepath):
        return jsonify({"success": False, "error": "報告不存在"}), 404

    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()

    return jsonify({"success": True, "filename": filename, "content": content})


def _list_reports():
    """掃描報告目錄，回傳報告清單"""
    if not os.path.isdir(AUDIT_REPORTS_DIR):
        return []

    reports = []
    for fname in os.listdir(AUDIT_REPORTS_DIR):
        if not _SAFE_FILENAME.match(fname):
            continue
        filepath = os.path.join(AUDIT_REPORTS_DIR, fname)
        stat = os.stat(filepath)

        # 從檔名解析 hostname 和日期
        parts = fname.replace("Audit_Report_", "").replace(".txt", "")
        date_str = parts[-8:]
        hostname = parts[:-9]

        try:
            date_formatted = f"{date_str[:4]}-{date_str[4:6]}-{date_str[6:8]}"
        except (IndexError, ValueError):
            date_formatted = date_str

        reports.append({
            "filename": fname,
            "hostname": hostname,
            "date": date_formatted,
            "size_kb": round(stat.st_size / 1024, 1),
            "mtime": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        })

    reports.sort(key=lambda x: x["mtime"], reverse=True)
    return reports


# ─── 稽核參數設定 ───
def _get_audit_config(db=None):
    if db is None:
        db = get_db()
    doc = db.settings.find_one({"_id": "security_audit_config"})
    defaults = {
        "audit_cat1": "1",
        "audit_cat2": "1",
        "audit_cat3": "1",
        "audit_cat4": "1",
        "audit_cat5": "1",
        "audit_cat6": "1",
        "audit_large_lines": "100",
        "audit_last_n": "20",
        "audit_archive": "1",
        "audit_svc_head": "30",
        "audit_services_head": "50",
    }
    if doc:
        for k in defaults:
            if k in doc:
                defaults[k] = doc[k]
    return defaults


@bp.route("/api/security-audit/config", methods=["GET"])
@admin_required
def get_config():
    return jsonify({"success": True, "data": _get_audit_config()})


@bp.route("/api/security-audit/config", methods=["PUT"])
@admin_required
def update_config():
    data = request.get_json(force=True) if request.is_json else {}
    db = get_db()
    allowed = list(_get_audit_config(db).keys())
    update = {k: str(v) for k, v in data.items() if k in allowed}
    update["updated_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    db.settings.update_one({"_id": "security_audit_config"}, {"$set": update}, upsert=True)
    return jsonify({"success": True, "message": "參數已儲存"})
