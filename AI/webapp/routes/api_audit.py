from decorators import login_required
"""帳號盤點 API Blueprint - /api/audit/* (不需登入)"""
from flask import Blueprint, request, jsonify, Response
import sys, os, json, csv, io
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.mongo_service import get_collection, get_hosts_col, get_all_settings, update_setting
from config import INSPECTION_HOME

bp = Blueprint("api_audit", __name__, url_prefix="/api/audit")


def _get_audit_data():
    """取得帳號盤點資料（從 account_audit collection 讀取最新資料）"""
    audit_col = get_collection("account_audit")
    notes_col = get_collection("account_notes")
    hr_col = get_collection("hr_users")
    hosts_col = get_hosts_col()
    settings_col = get_collection("settings")

    pw_days = 180
    login_days = 180
    th = settings_col.find_one({"key": "audit_password_days"})
    if th:
        pw_days = int(th.get("value", 180))
    th2 = settings_col.find_one({"key": "audit_login_days"})
    if th2:
        login_days = int(th2.get("value", 180))

    pipeline = [
        {"$sort": {"run_date": -1}},
        {"$group": {
            "_id": {"hostname": "$hostname", "user": "$user"},
            "doc": {"$first": "$$ROOT"},
        }},
        {"$replaceRoot": {"newRoot": "$doc"}},
        {"$project": {"_id": 0}},
    ]
    audits = list(audit_col.aggregate(pipeline))

    hr_lookup = {}
    for hr in hr_col.find({}, {"_id": 0}):
        ad = (hr.get("ad_account") or "").lower()
        if ad:
            hr_lookup[ad] = hr

    notes_lookup = {}
    for note in notes_col.find({}, {"_id": 0}):
        key = f"{note.get('hostname', '')}_{note.get('user', '')}"
        notes_lookup[key] = note

    # v3.11.16.0: join 人工標記高權限
    priv_col = get_collection("account_privileged_flags")
    priv_lookup = {}
    for p in priv_col.find({}, {"_id": 0}):
        key = f"{p.get('hostname', '')}_{p.get('user', '')}"
        priv_lookup[key] = p

    hosts_lookup = {h["hostname"]: h for h in hosts_col.find(
        {}, {"_id": 0, "hostname": 1, "custodian": 1, "department": 1}
    )}

    linux_system = {"systemd-coredump", "sssd", "chrony", "systemd-oom", "polkitd",
                    "setroubleshoot", "saslauth", "dbus", "tss", "clevis",
                    "cockpit-ws", "cockpit-wsinstance", "flatpak", "gnome-initial-setup",
                    "colord", "geoclue", "pipewire", "rtkit", "abrt", "unbound",
                    "radvd", "qemu", "usbmuxd", "gluster", "rpcuser", "nfsnobody",
                    "systemd-network", "systemd-timesync", "messagebus", "sshd"}

    result = []
    for acct in audits:
        user = acct.get("user", "")
        hostname = acct.get("hostname", "")
        if user.lower() in linux_system:
            continue

        hr = hr_lookup.get(user.lower(), {})
        note_key = f"{hostname}_{user}"
        note_data = notes_lookup.get(note_key, {})
        host_info = hosts_lookup.get(hostname, {})

        pw_age = acct.get("pw_age_days", 0)
        login_age = acct.get("login_age_days", 0)
        if isinstance(pw_age, str):
            pw_age = int(pw_age) if pw_age.isdigit() else 9999
        if isinstance(login_age, str):
            login_age = int(login_age) if login_age.isdigit() else 9999

        risks = acct.get("risks") or []
        if not risks:
            if pw_age >= pw_days:
                risks.append({"type": "pw_old", "desc": f"密碼 {pw_age} 天未變更", "level": "warn"})
            if acct.get("pw_expired"):
                risks.append({"type": "pw_expired", "desc": "密碼已到期", "level": "error"})
            if login_age >= login_days:
                risks.append({"type": "no_login", "desc": f"{login_age} 天未登入", "level": "warn"})

        priv_key = f"{hostname}_{user}"
        priv_data = priv_lookup.get(priv_key, {})

        result.append({
            "hostname": hostname,
            "user": user,
            "uid": acct.get("uid", ""),
            "gid": acct.get("gid", ""),                          # v3.11.16.0 補傳
            "primary_group": acct.get("primary_group", ""),      # v3.11.16.0 補傳
            "enabled": acct.get("enabled", True),
            "locked": acct.get("locked", ""),
            "pw_last_change": acct.get("pw_last_change", ""),
            "pw_expires": acct.get("pw_expires", ""),
            "pw_age_days": pw_age,
            "last_login": acct.get("last_login", ""),
            "login_age_days": login_age,
            "risks": risks,
            "risk_count": acct.get("risk_count", len(risks)),
            "note": note_data.get("note", "") or acct.get("note", ""),
            "department": note_data.get("department", "") or hr.get("department", hr.get("部門", "")) or host_info.get("department", ""),
            "hr_name": hr.get("name", hr.get("姓名", "")) or acct.get("hr_name", ""),
            "hr_emp_id": hr.get("emp_id", hr.get("工號", "")),
            "run_date": acct.get("run_date", ""),
            # v3.11.16.0: 人工標記高權限
            "is_privileged_manual": bool(priv_data),
            "privileged_reason": priv_data.get("reason", ""),
            "privileged_marked_by": priv_data.get("marked_by", ""),
            "privileged_marked_at": priv_data.get("marked_at", ""),
        })

    result.sort(key=lambda x: (-x["risk_count"], x["hostname"], x["user"]))
    return result, {"pw_days": pw_days, "login_days": login_days}


@bp.route("/accounts", methods=["GET"])
def audit_accounts():
    data, thresholds = _get_audit_data()
    return jsonify({"success": True, "data": data, "count": len(data), "thresholds": thresholds})


@bp.route("/export", methods=["GET"])
@login_required
def export_audit():
    data, _ = _get_audit_data()
    output = io.StringIO()
    fields = ["hostname", "user", "department", "hr_name", "hr_emp_id", "note",
              "enabled", "pw_last_change", "pw_expires", "pw_age_days",
              "last_login", "login_age_days", "risk_count"]
    writer = csv.DictWriter(output, fieldnames=fields, extrasaction="ignore")
    writer.writeheader()
    for d in data:
        writer.writerow(d)
    return Response(
        "\ufeff" + output.getvalue(),
        mimetype="text/csv; charset=utf-8",
        headers={"Content-Disposition": f"attachment;filename=account_audit_{datetime.now().strftime('%Y%m%d')}.csv"}
    )


# ========== Run audit (manual trigger) ==========
import subprocess, threading

_audit_run_state = {"running": False, "started_at": None, "finished_at": None, "exit_code": None, "last_log": ""}


def _run_audit_worker():
    global _audit_run_state
    from datetime import datetime
    try:
        script = os.path.join(INSPECTION_HOME, "run_inspection.sh")
        r = subprocess.run(["/bin/bash", script], capture_output=True, text=True, timeout=1800)
        _audit_run_state["exit_code"] = r.returncode
        _audit_run_state["last_log"] = (r.stdout or "")[-2000:] + "\n" + (r.stderr or "")[-500:]
    except Exception as e:
        _audit_run_state["exit_code"] = -1
        _audit_run_state["last_log"] = f"ERROR: {e}"
    finally:
        _audit_run_state["running"] = False
        _audit_run_state["finished_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")


@bp.route("/run", methods=["POST"])
@login_required
def run_audit_scan():
    from datetime import datetime
    global _audit_run_state
    if _audit_run_state["running"]:
        return jsonify({
            "success": False,
            "error": "盤點正在進行中",
            "started_at": _audit_run_state["started_at"],
        }), 409
    _audit_run_state.update({
        "running": True,
        "started_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "finished_at": None,
        "exit_code": None,
        "last_log": "",
    })
    t = threading.Thread(target=_run_audit_worker, daemon=True)
    t.start()
    return jsonify({"success": True, "message": "盤點已啟動，預計 2-5 分鐘", "started_at": _audit_run_state["started_at"]})


@bp.route("/run/status", methods=["GET"])
def run_audit_status():
    audit_col = get_collection("account_audit")
    last = audit_col.find_one({}, sort=[("run_date", -1), ("_id", -1)])
    last_run = last.get("run_date", "") if last else ""
    return jsonify({
        "success": True,
        "running": _audit_run_state["running"],
        "started_at": _audit_run_state["started_at"],
        "finished_at": _audit_run_state["finished_at"],
        "exit_code": _audit_run_state["exit_code"],
        "last_run_date": last_run,
    })


# ========== v3.11.16.0: 人工標記高權限 (Phase 2) ==========
@bp.route("/privileged", methods=["GET"])
@login_required
def list_privileged():
    """列出所有人工標記的高權限帳號 (Phase 3 簽核頁會用)"""
    col = get_collection("account_privileged_flags")
    data = list(col.find({}, {"_id": 0}).sort([("hostname", 1), ("user", 1)]))
    return jsonify({"success": True, "data": data, "count": len(data)})


@bp.route("/privileged", methods=["POST"])
@login_required
def mark_privileged():
    """標記帳號為高權限 (強制備註)
    body: {hostname, user, reason, marked_by?}
    """
    if not request.is_json:
        return jsonify({"success": False, "error": "需要 JSON"}), 400
    hostname = (request.json.get("hostname") or "").strip()
    user = (request.json.get("user") or "").strip()
    reason = (request.json.get("reason") or "").strip()
    marked_by = (request.json.get("marked_by") or "").strip()
    if not hostname or not user:
        return jsonify({"success": False, "error": "缺少 hostname / user"}), 400
    if not reason:
        # v3.11.16.0: 強制備註 — 為什麼是高權限必須說明才能歸檔
        return jsonify({"success": False, "error": "備註為必填 (為什麼是高權限)"}), 400

    col = get_collection("account_privileged_flags")
    col.create_index([("hostname", 1), ("user", 1)], unique=True)
    doc = {
        "hostname": hostname,
        "user": user,
        "reason": reason,
        "marked_by": marked_by,
        "marked_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }
    col.update_one({"hostname": hostname, "user": user}, {"$set": doc}, upsert=True)
    return jsonify({"success": True, "message": f"已標記 {hostname}/{user} 為高權限"})


@bp.route("/privileged", methods=["DELETE"])
@login_required
def unmark_privileged():
    """取消人工高權限標記 (不影響 UID/GID=0 的自動判定)
    body: {hostname, user}
    """
    if not request.is_json:
        return jsonify({"success": False, "error": "需要 JSON"}), 400
    hostname = (request.json.get("hostname") or "").strip()
    user = (request.json.get("user") or "").strip()
    if not hostname or not user:
        return jsonify({"success": False, "error": "缺少 hostname / user"}), 400

    col = get_collection("account_privileged_flags")
    r = col.delete_one({"hostname": hostname, "user": user})
    if r.deleted_count == 0:
        return jsonify({"success": False, "error": "找不到該標記"}), 404
    return jsonify({"success": True, "message": f"已取消 {hostname}/{user} 高權限標記"})


# ========== v3.11.14.0: View /etc/passwd on target host ==========
@bp.route("/passwd", methods=["GET"])
@login_required
def get_remote_passwd():
    """即時透過 ansible 抓目標主機的 /etc/passwd 原文
    Query: hostname (必填, 需對應 inventory 裡的 host)
    Return: {success, hostname, content, lines}
    """
    import re
    hostname = (request.args.get("hostname") or "").strip()
    if not hostname:
        return jsonify({"success": False, "error": "hostname required"}), 400
    # 白名單: 只允許 inventory 裡的 hostname 字元(防 shell injection)
    if not re.match(r"^[\w.\-]+$", hostname):
        return jsonify({"success": False, "error": "invalid hostname"}), 400

    ansible_dir = os.path.join(INSPECTION_HOME, "ansible")
    vault_pass = os.path.join(INSPECTION_HOME, ".vault_pass")
    vault_arg = f"--vault-password-file {vault_pass}" if os.path.exists(vault_pass) else ""
    cmd = (
        f"cd {ansible_dir} && "
        f'ansible {hostname} -i inventory/hosts.yml -m command -a "cat /etc/passwd" {vault_arg}'
    )
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        if result.returncode != 0:
            return jsonify({
                "success": False,
                "error": "ansible failed",
                "stderr": (result.stderr or "")[-500:],
                "stdout": (result.stdout or "")[-500:],
            }), 500
        # ansible 輸出: "<hostname> | CHANGED | rc=0 >>\n<passwd content>"
        parts = result.stdout.split("\n", 1)
        if len(parts) < 2:
            return jsonify({"success": False, "error": "unexpected output", "raw": result.stdout[:500]}), 500
        content = parts[1].rstrip()
        lines = [ln for ln in content.split("\n") if ln.strip()]
        return jsonify({
            "success": True,
            "hostname": hostname,
            "content": content,
            "lines": len(lines),
        })
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "error": "timeout (>30s)"}), 504
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500
