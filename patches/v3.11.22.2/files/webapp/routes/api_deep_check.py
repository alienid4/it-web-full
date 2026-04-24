"""深度檢查 API (v3.11.22.0) — 單機 Linux 9 面向深度診斷 (smit_menu mod_troubleshoot.sh -m)"""
from flask import Blueprint, jsonify, request, send_file
import subprocess
import threading
import os
import re
import json
import socket
from datetime import datetime
from services.mongo_service import get_db
from decorators import login_required, admin_required

bp = Blueprint("api_deep_check", __name__)


def _detect_inspection_home():
    """偵測 inspection 家目錄。優先 env var (INSPECTION_HOME / ITAGENT_HOME)，
    再試常見路徑 /opt/inspection (公司 13+) 和 /seclog/AI/inspection (家裡 221)"""
    for var in ("INSPECTION_HOME", "ITAGENT_HOME"):
        val = os.environ.get(var)
        if val and os.path.isdir(val):
            return val
    for candidate in ("/opt/inspection", "/seclog/AI/inspection"):
        if os.path.isdir(candidate):
            return candidate
    return "/opt/inspection"  # 最後 fallback


INSPECTION_HOME = _detect_inspection_home()
ANSIBLE_DIR = os.path.join(INSPECTION_HOME, "ansible")
VAULT_PASS = os.path.join(INSPECTION_HOME, ".vault_pass")
REPORTS_DIR = os.path.join(INSPECTION_HOME, "data", "deep_check_reports")
PROGRESS_DIR = os.path.join(INSPECTION_HOME, "data", "deep_check_progress")

# 報告檔名 pattern: ts_<hostname>_<YYYYMMDD_HHMMSS>_{summary,detail}.txt
_SAFE_FILENAME = re.compile(r'^ts_[\w\-\.]+_\d{8}_\d{6}_(summary|detail)\.txt$')
_SAFE_HOSTNAME = re.compile(r'^[\w\.\-]+$')
_jobs = {}

# controller 自己不能做深度檢查 (ansible become:true 需 sudo 密碼)
_CONTROLLER_HOSTNAME = os.environ.get("INSPECTION_CONTROLLER_HOSTNAME", socket.gethostname())


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


@bp.route("/api/deep-check/meta", methods=["GET"])
@login_required
def get_meta():
    """回傳深度檢查相關的 meta info (前端渲染用)"""
    return jsonify({
        "success": True,
        "controller_hostname": _CONTROLLER_HOSTNAME,
    })


@bp.route("/api/deep-check/run", methods=["POST"])
@login_required
def run_deep_check():
    """觸發單台主機的深度檢查 (非同步)"""
    # 防重複執行
    for jid, j in _jobs.items():
        if j["status"] == "running":
            return jsonify({"success": False, "error": "已有深度檢查任務進行中", "job_id": jid}), 409

    data = request.get_json(force=True) if request.is_json else {}
    hostname = (data.get("hostname") or "").strip()

    if not hostname:
        return jsonify({"success": False, "error": "需要 hostname"}), 400
    if not _SAFE_HOSTNAME.match(hostname):
        return jsonify({"success": False, "error": f"無效主機名: {hostname}"}), 400

    # 驗證 hostname 存在且為 Linux 類
    db = get_db()
    host_doc = db.hosts.find_one(
        {"hostname": hostname, "os_group": {"$in": ["rocky", "rhel", "debian", "centos", "ubuntu"]}},
        {"hostname": 1, "ip": 1, "os": 1, "status": 1}
    )
    if not host_doc:
        return jsonify({"success": False, "error": f"找不到 Linux 主機: {hostname}"}), 404
    if host_doc.get("status") == "disabled":
        return jsonify({"success": False, "error": f"主機已停用: {hostname}"}), 400

    job_ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    job_id = f"dc_{job_ts}"
    os.makedirs(PROGRESS_DIR, exist_ok=True)
    log_path = os.path.join(PROGRESS_DIR, f"{job_id}.log")

    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""
    # v3.11.22.2: 把 INSPECTION_HOME 傳給 playbook (否則 playbook 會 fallback 成 hardcode 路徑)
    extra_vars = {
        "job_timestamp": job_ts,
        "inspection_home_override": INSPECTION_HOME,
    }
    ev_file = os.path.join(PROGRESS_DIR, f"{job_id}_vars.json")
    with open(ev_file, "w") as f:
        json.dump(extra_vars, f)

    cmd = (
        f"ansible-playbook playbooks/deep_check.yml "
        f"-i inventory/hosts.yml --limit {hostname} {vault_arg} "
        f"-e @{ev_file}"
    )

    _jobs[job_id] = {
        "status": "starting",
        "target_hosts": [hostname],
        "host_ip_map": {hostname: host_doc.get("ip", "")},
        "log_path": log_path,
        "job_ts": job_ts,
        "started_at": datetime.now().strftime("%H:%M:%S"),
        "finished_at": None,
        "pid": None,
    }

    t = threading.Thread(target=_run_async, args=(job_id, cmd, [hostname], log_path))
    t.daemon = True
    t.start()

    return jsonify({
        "success": True,
        "job_id": job_id,
        "message": f"深度檢查已啟動: {hostname}",
        "hostname": hostname,
    })


@bp.route("/api/deep-check/progress/<job_id>", methods=["GET"])
@login_required
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
        if s == "done":
            done_count += 1
        hosts_detail.append({"hostname": h, "ip": host_ip_map.get(h, ""), "status": s})
    is_finished = job["status"] in ("done", "error", "timeout")

    # 完成時嘗試找對應報告檔名
    report_files = {}
    if is_finished and job["status"] == "done":
        hostname = job["target_hosts"][0]
        job_ts = job.get("job_ts", "")
        for kind in ("summary", "detail"):
            fname = f"ts_{hostname}_{job_ts}_{kind}.txt"
            if os.path.isfile(os.path.join(REPORTS_DIR, fname)):
                report_files[kind] = fname

    log_content = None
    if is_finished and os.path.isfile(job["log_path"]):
        try:
            with open(job["log_path"], "r", encoding="utf-8", errors="replace") as f:
                log_content = f.read()[-5000:]
        except Exception:
            pass

    return jsonify({
        "success": True,
        "job_id": job_id,
        "job_status": job["status"],
        "phase": progress["phase"],
        "total": len(job["target_hosts"]),
        "completed": done_count,
        "hosts": hosts_detail,
        "started_at": job["started_at"],
        "finished_at": job.get("finished_at"),
        "is_finished": is_finished,
        "log": log_content,
        "report_files": report_files,
    })


@bp.route("/api/deep-check/reports", methods=["GET"])
@login_required
def list_reports():
    """列出所有深度檢查報告, 可用 ?hostname= 過濾"""
    hostname_filter = (request.args.get("hostname") or "").strip()
    return jsonify({"success": True, "data": _list_reports(hostname_filter)})


@bp.route("/api/deep-check/reports/<filename>/preview", methods=["GET"])
@login_required
def preview_report(filename):
    if not _SAFE_FILENAME.match(filename):
        return jsonify({"success": False, "error": "無效檔名"}), 400
    fp = os.path.join(REPORTS_DIR, filename)
    if not os.path.isfile(fp):
        return jsonify({"success": False, "error": "不存在"}), 404
    with open(fp, "r", encoding="utf-8", errors="replace") as f:
        content = f.read()
    return jsonify({"success": True, "filename": filename, "content": content})


@bp.route("/api/deep-check/reports/<filename>/download", methods=["GET"])
@login_required
def download_report(filename):
    if not _SAFE_FILENAME.match(filename):
        return jsonify({"success": False, "error": "無效檔名"}), 400
    fp = os.path.join(REPORTS_DIR, filename)
    if not os.path.isfile(fp):
        return jsonify({"success": False, "error": "不存在"}), 404
    return send_file(fp, as_attachment=True, download_name=filename)


def _list_reports(hostname_filter=""):
    if not os.path.isdir(REPORTS_DIR):
        return []
    reports = []
    for fname in os.listdir(REPORTS_DIR):
        if not _SAFE_FILENAME.match(fname):
            continue
        # ts_<hostname>_<YYYYMMDD_HHMMSS>_<kind>.txt
        m = re.match(r'^ts_(.+)_(\d{8})_(\d{6})_(summary|detail)\.txt$', fname)
        if not m:
            continue
        hostname, ymd, hms, kind = m.groups()
        if hostname_filter and hostname != hostname_filter:
            continue
        fp = os.path.join(REPORTS_DIR, fname)
        stat = os.stat(fp)
        date_f = f"{ymd[:4]}-{ymd[4:6]}-{ymd[6:8]} {hms[:2]}:{hms[2:4]}:{hms[4:6]}"
        reports.append({
            "filename": fname,
            "hostname": hostname,
            "kind": kind,
            "date": date_f,
            "size_kb": round(stat.st_size / 1024, 1),
            "mtime": datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S"),
            "job_ts": f"{ymd}_{hms}",
        })
    reports.sort(key=lambda x: x["mtime"], reverse=True)
    return reports
