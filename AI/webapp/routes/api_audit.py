from decorators import login_required
"""帳號盤點 API Blueprint - /api/audit/* (不需登入)"""
from flask import Blueprint, request, jsonify, Response
import sys, os, json, csv, io
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.mongo_service import get_collection, get_all_settings, update_setting
from config import INSPECTION_HOME

bp = Blueprint("api_audit", __name__, url_prefix="/api/audit")


def _get_audit_data():
    """取得帳號盤點資料（共用邏輯）"""
    col = get_collection("inspections")
    notes_col = get_collection("account_notes")
    hr_col = get_collection("hr_users")
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
        {"$sort": {"run_date": -1, "run_time": -1}},
        {"$group": {"_id": "$hostname", "doc": {"$first": "$$ROOT"}}},
        {"$replaceRoot": {"newRoot": "$doc"}},
        {"$project": {"_id": 0}},
    ]
    inspections = list(col.aggregate(pipeline))

    hr_lookup = {}
    for hr in hr_col.find({}, {"_id": 0}):
        ad = hr.get("ad_account", "").lower()
        if ad:
            hr_lookup[ad] = hr

    notes_lookup = {}
    for note in notes_col.find({}, {"_id": 0}):
        key = f"{note.get('hostname', '')}_{note.get('user', '')}"
        notes_lookup[key] = note

    linux_system = {"systemd-coredump", "sssd", "chrony", "systemd-oom", "polkitd",
                    "setroubleshoot", "saslauth", "dbus", "tss", "clevis",
                    "cockpit-ws", "cockpit-wsinstance", "flatpak", "gnome-initial-setup",
                    "colord", "geoclue", "pipewire", "rtkit", "abrt", "unbound",
                    "radvd", "qemu", "usbmuxd", "gluster", "rpcuser", "nfsnobody",
                    "systemd-network", "systemd-timesync", "messagebus", "sshd"}

    result = []
    for insp in inspections:
        hostname = insp.get("hostname", "")
        audit_data = insp.get("results", {}).get("account_audit", [])
        for acct in audit_data:
            user = acct.get("user", "")
            if user.lower() in linux_system:
                continue

            hr = hr_lookup.get(user.lower(), {})
            note_key = f"{hostname}_{user}"
            note_data = notes_lookup.get(note_key, {})

            risks = []
            pw_age = acct.get("pw_age_days", 0)
            login_age = acct.get("login_age_days", 0)
            if isinstance(pw_age, str):
                pw_age = int(pw_age) if pw_age.isdigit() else 9999
            if isinstance(login_age, str):
                login_age = int(login_age) if login_age.isdigit() else 9999

            if pw_age >= pw_days:
                risks.append({"type": "pw_old", "desc": f"密碼 {pw_age} 天未變更", "level": "warn"})
            if acct.get("pw_expired"):
                risks.append({"type": "pw_expired", "desc": "密碼已到期", "level": "error"})
            if login_age >= login_days:
                risks.append({"type": "no_login", "desc": f"{login_age} 天未登入", "level": "warn"})

            result.append({
                "hostname": hostname,
                "user": user,
                "uid": acct.get("uid", ""),
                "enabled": acct.get("enabled", True),
                "locked": acct.get("locked", ""),
                "pw_last_change": acct.get("pw_last_change", ""),
                "pw_expires": acct.get("pw_expires", ""),
                "pw_age_days": pw_age,
                "last_login": acct.get("last_login", ""),
                "login_age_days": login_age,
                "risks": risks,
                "risk_count": len(risks),
                "note": note_data.get("note", ""),
                "department": note_data.get("department", "") or hr.get("department", hr.get("部門", "")),
                "hr_name": hr.get("name", hr.get("姓名", "")),
                "hr_emp_id": hr.get("emp_id", hr.get("工號", "")),
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
