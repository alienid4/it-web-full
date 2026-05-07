"""效能月報 API (nmon)"""
import os
import csv
import io
import json
import subprocess
from datetime import datetime
from flask import Blueprint, request, jsonify, Response
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from decorators import login_required, admin_required
from services import nmon_service, nmon_charts
from services.mongo_service import get_collection, get_hosts_col

bp = Blueprint("api_nmon", __name__, url_prefix="/api/nmon")

INSPECTION_HOME = os.environ.get("INSPECTION_HOME", "/opt/inspection")
ANSIBLE_DIR = os.path.join(INSPECTION_HOME, "ansible")
VAULT_PASS = os.path.join(INSPECTION_HOME, ".vault_pass")


@bp.route("/hosts", methods=["GET"])
@login_required
def hosts():
    """回傳 nmon_enabled=True 的主機 + 有多少 daily 資料"""
    enabled = nmon_service.list_enabled_hosts()
    daily_col = get_collection("nmon_daily")
    for h in enabled:
        h["daily_count"] = daily_col.count_documents({"hostname": h["hostname"]})
        last = daily_col.find_one(
            {"hostname": h["hostname"]},
            sort=[("date", -1)],
            projection={"_id": 0, "date": 1},
        )
        h["last_date"] = last["date"] if last else None
    return jsonify({"success": True, "data": enabled, "count": len(enabled)})


@bp.route("/monthly", methods=["GET"])
@login_required
def monthly():
    """月報資料: ?host=X&month=2026-04"""
    host = (request.args.get("host") or "").strip()
    month_str = (request.args.get("month") or "").strip()
    if not host or not month_str:
        return jsonify({"success": False, "error": "host+month required (month=YYYY-MM)"}), 400
    try:
        year, month = month_str.split("-")
        year, month = int(year), int(month)
    except Exception:
        return jsonify({"success": False, "error": "month format YYYY-MM"}), 400
    data = nmon_service.get_monthly_report(host, year, month)
    return jsonify({"success": True, "data": data})


@bp.route("/toggle", methods=["POST"])
@admin_required
def toggle():
    """{host, enabled} — 單台 toggle (保留相容)"""
    body = request.get_json(silent=True) or {}
    host = (body.get("host") or "").strip()
    enabled = bool(body.get("enabled"))
    if not host:
        return jsonify({"success": False, "error": "host required"}), 400
    col = get_hosts_col()
    r = col.update_one({"hostname": host}, {"$set": {"nmon_enabled": enabled}})
    if r.matched_count == 0:
        return jsonify({"success": False, "error": f"host {host} not found"}), 404
    return jsonify({"success": True, "hostname": host, "nmon_enabled": enabled})


# ---------- 排程管理 (GET/POST) v3.17.15.0: IBM fixed dual cron ----------

@bp.route("/schedule", methods=["GET"])
@login_required
def schedule_get():
    """回全部主機 + nmon 啟用狀態 (IBM 固定雙 cron, 不再有 interval 選項)"""
    hosts_col = get_hosts_col()
    hosts = list(hosts_col.find({}, {
        "_id": 0, "hostname": 1, "ip": 1, "os": 1, "os_group": 1,
        "system_name": 1, "tier": 1, "nmon_enabled": 1, "nmon_deployed_at": 1,
    }).sort("hostname", 1))

    for h in hosts:
        og = (h.get("os_group") or "").lower()
        supported = og in ("rocky", "rhel", "centos", "debian", "ubuntu", "aix", "linux")
        h["nmon_supported"] = supported
        h["nmon_enabled"] = bool(h.get("nmon_enabled"))

    return jsonify({
        "success": True,
        "data": {
            "hosts": hosts,
            "schedule": {
                "daily_monitoring": "0 0 * * * nmon -f -t -s 60 -c 1440 -m /var/log/nmon/daily",
                "monthly_capacity": "0 0 * * * nmon -f -t -s 900 -c 96 -m /var/log/nmon/monthly",
                "description": "IBM recommended: daily/weekly=60s x 1440, monthly capacity=900s x 96",
            },
            "enabled_count": sum(1 for h in hosts if h["nmon_enabled"]),
        },
    })


@bp.route("/schedule/preview", methods=["POST"])
@admin_required
def schedule_preview():
    """body: {hostnames: [...]}  回: to_enable / to_disable / skipped_windows"""
    body = request.get_json(silent=True) or {}
    want_hostnames = set(body.get("hostnames") or [])

    hosts_col = get_hosts_col()
    all_hosts = list(hosts_col.find({}, {"_id": 0, "hostname": 1, "os_group": 1, "nmon_enabled": 1}))

    def _is_windows(h):
        return (h.get("os_group") or "").lower() in ("windows", "win")

    to_enable, to_disable, skipped_windows = [], [], []
    for h in all_hosts:
        hn = h["hostname"]
        was = bool(h.get("nmon_enabled"))
        want = hn in want_hostnames
        if want and _is_windows(h):
            skipped_windows.append(hn)
        elif want and not was:
            to_enable.append(hn)
        elif not want and was:
            to_disable.append(hn)

    return jsonify({
        "success": True,
        "data": {"to_enable": to_enable, "to_disable": to_disable, "skipped_windows": skipped_windows},
    })


@bp.route("/schedule", methods=["POST"])
@admin_required
def schedule_post():
    """body: {hostnames: [...], confirm: true}  部署 IBM 雙 cron 或清 cron"""
    body = request.get_json(silent=True) or {}
    if not body.get("confirm"):
        return jsonify({"success": False, "error": "confirm=true required (preview first)"}), 400

    want_hostnames = set(body.get("hostnames") or [])
    hosts_col = get_hosts_col()
    all_hosts = list(hosts_col.find({}, {"_id": 0, "hostname": 1, "os_group": 1, "nmon_enabled": 1}))

    def _is_windows(h):
        return (h.get("os_group") or "").lower() in ("windows", "win")

    to_enable, to_disable, skipped_windows = [], [], []
    now_ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    for h in all_hosts:
        hn = h["hostname"]
        was = bool(h.get("nmon_enabled"))
        want = hn in want_hostnames
        if want and _is_windows(h):
            skipped_windows.append(hn); continue
        if want:
            hosts_col.update_one({"hostname": hn}, {"$set": {"nmon_enabled": True, "nmon_deployed_at": now_ts}})
            to_enable.append(hn)
        elif was:
            hosts_col.update_one({"hostname": hn}, {"$set": {"nmon_enabled": False, "nmon_removed_at": now_ts}})
            to_disable.append(hn)

    logdir = os.path.join(INSPECTION_HOME, "logs")
    os.makedirs(logdir, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""

    deploy_log = None
    if to_enable:
        log_name = f"nmon_schedule_deploy_{stamp}.log"
        log_path = os.path.join(logdir, log_name)
        limit_arg = ":".join(to_enable)
        deploy_cmd = (f"cd {ANSIBLE_DIR} && ansible-playbook -i inventory/hosts.yml {vault_arg} "
                      f"playbooks/collect_nmon.yml --limit '{limit_arg}'")
        try:
            subprocess.Popen(["bash", "-c", f"nohup bash -c '{deploy_cmd}' > {log_path} 2>&1 &"],
                             close_fds=True)
            deploy_log = log_name
        except Exception as e:
            return jsonify({"success": False, "error": f"deploy spawn failed: {e}"}), 500

    remove_log = None
    if to_disable:
        remove_log = f"nmon_schedule_remove_{stamp}.log"
        remove_path = os.path.join(logdir, remove_log)
        limit_arg = ":".join(to_disable)
        remove_cmd = (f"cd {ANSIBLE_DIR} && ansible-playbook -i inventory/hosts.yml {vault_arg} "
                      f"playbooks/remove_nmon.yml --limit '{limit_arg}'")
        try:
            subprocess.Popen(["bash", "-c", f"nohup bash -c '{remove_cmd}' > {remove_path} 2>&1 &"],
                             close_fds=True)
        except Exception as e:
            return jsonify({"success": False, "error": f"remove spawn failed: {e}"}), 500

    msg_parts = []
    if to_enable: msg_parts.append(f"部署 {len(to_enable)} 台 (IBM 雙 cron: 日報+月報)")
    if to_disable: msg_parts.append(f"移除 {len(to_disable)} 台 cron (歷史資料保留)")
    if skipped_windows: msg_parts.append(f"跳過 {len(skipped_windows)} 台 Windows")
    if not msg_parts: msg_parts.append("無變更")

    return jsonify({
        "success": True,
        "data": {
            "enabled_count": len(to_enable),
            "to_enable": to_enable,
            "to_disable": to_disable,
            "skipped_windows": skipped_windows,
            "deploy_log": deploy_log,
            "remove_log": remove_log,
            "message": "；".join(msg_parts),
        },
    })

@bp.route("/import", methods=["POST"])
@admin_required
def do_import():
    """掃 data/nmon/*/*.nmon 匯入 MongoDB"""
    r = nmon_service.import_nmon_files()
    return jsonify({"success": True, "data": r})


@bp.route("/collect", methods=["POST"])
@admin_required
def collect():
    """觸發 Ansible playbook 抓所有 nmon_enabled 主機最近 2 天 .nmon"""
    enabled = [h["hostname"] for h in nmon_service.list_enabled_hosts()]
    if not enabled:
        return jsonify({"success": False, "error": "沒有主機開 nmon_enabled"}), 400
    limit_arg = ":".join(enabled)
    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""

    cmd = (
        f"cd {ANSIBLE_DIR} && ansible-playbook -i inventory/hosts.yml {vault_arg} "
        f"playbooks/collect_nmon.yml --limit '{limit_arg}'"
    )
    logdir = os.path.join(INSPECTION_HOME, "logs")
    os.makedirs(logdir, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    logfile = os.path.join(logdir, f"nmon_collect_{stamp}.log")
    full = f"nohup bash -c '{cmd}' > {logfile} 2>&1 &"
    try:
        subprocess.Popen(["bash", "-c", full], close_fds=True)
    except Exception as e:
        return jsonify({"success": False, "error": f"spawn failed: {e}"}), 500
    return jsonify({
        "success": True,
        "message": f"背景執行中，{len(enabled)} 台主機；完成後呼叫 /api/nmon/import 匯入",
        "log": os.path.basename(logfile),
        "limit": enabled,
    })


@bp.route("/export", methods=["GET"])
@login_required
def export_monthly():
    """月報 CSV 匯出: ?host=X&month=2026-04"""
    host = (request.args.get("host") or "").strip()
    month_str = (request.args.get("month") or "").strip()
    if not host or not month_str:
        return jsonify({"success": False, "error": "host+month required"}), 400
    try:
        year, month = [int(x) for x in month_str.split("-")]
    except Exception:
        return jsonify({"success": False, "error": "month format YYYY-MM"}), 400
    data = nmon_service.get_monthly_report(host, year, month)

    buf = io.StringIO()
    buf.write("\ufeff")
    w = csv.writer(buf)
    w.writerow([
        "日期", "CPU 峰值%", "CPU 均值%", "CPU 峰值時間",
        "記憶體 峰值%", "記憶體 均值%",
        "Disk 峰值%", "Disk 均值%", "最忙磁碟",
        "Net 峰值 KB/s", "Net 均值 KB/s",
    ])
    for d in data.get("dailies", []):
        w.writerow([
            d.get("date"),
            (d.get("cpu") or {}).get("peak"), (d.get("cpu") or {}).get("avg"), (d.get("cpu") or {}).get("peak_time"),
            (d.get("mem") or {}).get("peak"), (d.get("mem") or {}).get("avg"),
            (d.get("disk") or {}).get("peak"), (d.get("disk") or {}).get("avg"), (d.get("disk") or {}).get("peak_disk"),
            (d.get("net_kbps") or {}).get("peak"), (d.get("net_kbps") or {}).get("avg"),
        ])

    return Response(
        buf.getvalue(),
        mimetype="text/csv; charset=utf-8",
        headers={"Content-Disposition": f"attachment; filename=perf_{host}_{month_str}.csv"},
    )


@bp.route("/chart", methods=["GET"])
@login_required
def chart():
    """靜態 PNG: ?host=X&metric=cpu|mem|disk|net_kbps[&mode=monthly|weekly|daily][&month=YYYY-MM][&start=YYYY-MM-DD][&date=YYYY-MM-DD][&force=1]"""
    host = (request.args.get("host") or "").strip()
    metric = (request.args.get("metric") or "").strip().lower()
    mode = (request.args.get("mode") or "monthly").strip().lower()
    force = request.args.get("force") in ("1", "true", "yes")
    if not host or not metric:
        return jsonify({"success": False, "error": "host+metric required"}), 400

    try:
        if mode == "monthly":
            month_str = (request.args.get("month") or "").strip()
            if not month_str:
                return jsonify({"success": False, "error": "monthly mode requires month=YYYY-MM"}), 400
            year, month = [int(x) for x in month_str.split("-")]
            png, hit = nmon_charts.get_chart_png(host, metric, mode="monthly", year=year, month=month, force=force)
        elif mode == "weekly":
            start = (request.args.get("start") or "").strip()
            if not start:
                return jsonify({"success": False, "error": "weekly mode requires start=YYYY-MM-DD"}), 400
            png, hit = nmon_charts.get_chart_png(host, metric, mode="weekly", start=start, force=force)
        elif mode == "daily":
            date = (request.args.get("date") or "").strip()
            if not date:
                return jsonify({"success": False, "error": "daily mode requires date=YYYY-MM-DD"}), 400
            png, hit = nmon_charts.get_chart_png(host, metric, mode="daily", date=date, force=force)
        else:
            return jsonify({"success": False, "error": f"unknown mode: {mode}"}), 400
    except ValueError as e:
        return jsonify({"success": False, "error": str(e)}), 400
    except Exception as e:
        return jsonify({"success": False, "error": f"render failed: {e}"}), 500

    resp = Response(png, mimetype="image/png")
    resp.headers["Cache-Control"] = "public, max-age=300"
    resp.headers["X-Chart-Cache"] = "HIT" if hit else "MISS"
    return resp


@bp.route("/day", methods=["GET"])
@login_required
def day():
    """?host=X&date=YYYY-MM-DD → 單日 detail (KPI + timeseries)"""
    host = (request.args.get("host") or "").strip()
    date = (request.args.get("date") or "").strip()
    if not host or not date:
        return jsonify({"success": False, "error": "host+date required"}), 400
    data = nmon_service.get_day_report(host, date)
    return jsonify({"success": True, "data": data})


@bp.route("/week", methods=["GET"])
@login_required
def week():
    """?host=X&start=YYYY-MM-DD → 7 日 daily summary"""
    host = (request.args.get("host") or "").strip()
    start = (request.args.get("start") or "").strip()
    if not host or not start:
        return jsonify({"success": False, "error": "host+start required"}), 400
    data = nmon_service.get_week_report(host, start)
    return jsonify({"success": True, "data": data})


# v3.17.13.0+: NMON 部署狀態驗證面板
@bp.route("/verify", methods=["GET"])
@login_required
def verify_deployment():
    """對所有 nmon_enabled=true 的主機跑 ansible 4 項檢查 + DB 統計, 回 JSON.
    呼叫 scripts/verify_nmon.py --json. Sync (4-台 < 60s, 大規模再改 async).
    Response: {success, data: [{...host info...}], summary: {total, ok, partial, fail, unreachable}}
    """
    args = ["python3", os.path.join(INSPECTION_HOME, "scripts/verify_nmon.py"), "--json"]
    env = os.environ.copy()
    env["INSPECTION_HOME"] = INSPECTION_HOME
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=200, env=env, cwd=INSPECTION_HOME)
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "error": "verify_nmon.py timeout (200s)"}), 504
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500

    try:
        payload = json.loads(r.stdout) if r.stdout.strip() else {"hosts": [], "summary": {}}
    except json.JSONDecodeError as e:
        return jsonify({
            "success": False,
            "error": f"verify_nmon.py 輸出無法 parse: {e}",
            "stdout_head": r.stdout[:500],
            "stderr_head": r.stderr[:500],
        }), 500

    return jsonify({
        "success": r.returncode == 0,
        "data": payload.get("hosts", []),
        "summary": payload.get("summary", {}),
    })


# ============================================================================
# v3.17.14.0+: NMON 離線 RPM 派送 endpoint
# ============================================================================
# 用途: 對 EPEL 不通的隔離環境 (公司內網), 一鍵派送離線 nmon RPM 並安裝
# 對應 UI: 系統管理 → 監控平台管理 → 效能月報管理 → 「📊 NMON 部署狀態」 → 「📦 派送 RPM」
import re as _re_v3_17_14
import os as _os_v3_17_14
import subprocess as _sp_v3_17_14

@bp.route("/install-rpm", methods=["POST"])
@login_required
@admin_required
def install_nmon_rpm():
    """v3.17.14.0: 派送離線 nmon RPM 到指定主機.

    Request body: {"hostnames": ["host1", "host2", ...]}
    Response: {"success": bool, "stdout": str, "stderr": str, "returncode": int, "hostnames": [...]}
    """
    body = request.get_json(silent=True) or {}
    hostnames = body.get("hostnames") or []
    if not isinstance(hostnames, list) or not hostnames:
        return jsonify({"success": False, "error": "hostnames (list) required"}), 400

    # 主機名格式驗證 (避免 shell injection 走 --limit)
    safe_re = _re_v3_17_14.compile(r"^[a-zA-Z0-9._-]+$")
    invalid = [h for h in hostnames if not (isinstance(h, str) and safe_re.match(h))]
    if invalid:
        return jsonify({"success": False, "error": "invalid hostname format: " + str(invalid)}), 400

    # 偵測 INSPECTION_HOME (跟 run_inspection.sh 同邏輯)
    inspection_home = _os_v3_17_14.environ.get("INSPECTION_HOME")
    if not inspection_home:
        # routes/api_nmon.py → webapp/routes/ → webapp/ → INSPECTION_HOME
        here = _os_v3_17_14.path.dirname(_os_v3_17_14.path.abspath(__file__))
        inspection_home = _os_v3_17_14.path.dirname(_os_v3_17_14.path.dirname(here))

    ansible_dir = _os_v3_17_14.path.join(inspection_home, "ansible")
    playbook = _os_v3_17_14.path.join(ansible_dir, "playbooks", "install_nmon_rpm.yml")
    inventory = _os_v3_17_14.path.join(ansible_dir, "inventory", "hosts.yml")
    vault_pass = _os_v3_17_14.path.join(inspection_home, ".vault_pass")

    # 檢查檔案存在
    for path, label in [(playbook, "playbook"), (inventory, "inventory")]:
        if not _os_v3_17_14.path.exists(path):
            return jsonify({"success": False, "error": label + " not found: " + path}), 500

    limit_arg = ":".join(hostnames)
    cmd = [
        "ansible-playbook", playbook,
        "-i", inventory,
        "--limit", limit_arg,
        "--extra-vars", "inspection_home=" + inspection_home,
    ]
    if _os_v3_17_14.path.exists(vault_pass):
        cmd[1:1] = ["--vault-password-file", vault_pass]

    try:
        proc = _sp_v3_17_14.run(
            cmd, cwd=ansible_dir, capture_output=True, text=True, timeout=300
        )
        return jsonify({
            "success": proc.returncode == 0,
            "returncode": proc.returncode,
            "stdout": (proc.stdout or "")[-8000:],   # 最後 8KB
            "stderr": (proc.stderr or "")[-2000:],
            "hostnames": hostnames,
            "limit_arg": limit_arg,
        })
    except _sp_v3_17_14.TimeoutExpired:
        return jsonify({"success": False, "error": "ansible-playbook timeout (300s)"}), 504
    except Exception as e:
        return jsonify({"success": False, "error": "subprocess error: " + str(e)}), 500
