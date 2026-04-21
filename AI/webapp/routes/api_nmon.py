"""效能月報 API (nmon)"""
import os
import csv
import io
import subprocess
from datetime import datetime
from flask import Blueprint, request, jsonify, Response
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from decorators import login_required, admin_required
from services import nmon_service, nmon_charts
from services.mongo_service import get_collection

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
    col = get_collection("hosts")
    r = col.update_one({"hostname": host}, {"$set": {"nmon_enabled": enabled}})
    if r.matched_count == 0:
        return jsonify({"success": False, "error": f"host {host} not found"}), 404
    return jsonify({"success": True, "hostname": host, "nmon_enabled": enabled})


# ---------- 排程管理 (GET/POST) ----------
_INTERVAL_CHOICES = [1, 5, 15, 30, 60, 1440]


@bp.route("/schedule", methods=["GET"])
@login_required
def schedule_get():
    """回全部主機 + 現全域 interval + 當前選擇狀態"""
    settings_col = get_collection("settings")
    s = settings_col.find_one({"key": "nmon_interval_min"}, {"_id": 0, "value": 1}) or {}
    cur_interval = int(s.get("value") or 5)

    hosts_col = get_collection("hosts")
    hosts = list(hosts_col.find({}, {
        "_id": 0, "hostname": 1, "ip": 1, "os": 1, "os_group": 1,
        "system_name": 1, "tier": 1, "nmon_enabled": 1,
        "nmon_interval_min": 1, "nmon_deployed_at": 1,
    }).sort("hostname", 1))

    # 標記哪些不支援 (Windows 目前 role 還沒測、AS400/SNMP device 不適用)
    for h in hosts:
        og = (h.get("os_group") or "").lower()
        supported = og in ("rocky", "rhel", "centos", "debian", "ubuntu", "aix", "linux")
        h["nmon_supported"] = supported
        h["nmon_enabled"] = bool(h.get("nmon_enabled"))
        if h.get("nmon_interval_min") is None:
            h["nmon_interval_min"] = cur_interval

    return jsonify({
        "success": True,
        "data": {
            "hosts": hosts,
            "current_interval_min": cur_interval,
            "interval_choices": _INTERVAL_CHOICES,
            "enabled_count": sum(1 for h in hosts if h["nmon_enabled"]),
        },
    })


def _parse_host_configs(body):
    """
    支援兩種格式:
    新: host_configs = [{hostname, interval_min}]
    舊: {interval_min, hostnames} (全部套同一個 interval)
    回: dict {hostname: interval_min}
    """
    cfgs = body.get("host_configs")
    if isinstance(cfgs, list):
        out = {}
        for c in cfgs:
            hn = (c.get("hostname") or "").strip()
            iv = int(c.get("interval_min") or 5)
            if hn and iv in _INTERVAL_CHOICES:
                out[hn] = iv
        return out
    # 相容舊格式
    iv = int(body.get("interval_min") or 5)
    hs = [s.strip() for s in (body.get("hostnames") or []) if s]
    return {h: iv for h in hs if iv in _INTERVAL_CHOICES}


@bp.route("/schedule/preview", methods=["POST"])
@admin_required
def schedule_preview():
    """
    body: {host_configs: [{hostname, interval_min}, ...]}
    回: 分類 to_enable (含 interval) / to_disable / skipped_windows / changes
    """
    body = request.get_json(silent=True) or {}
    configs = _parse_host_configs(body)

    hosts_col = get_collection("hosts")
    all_hosts = list(hosts_col.find({}, {
        "_id": 0, "hostname": 1, "os_group": 1, "nmon_enabled": 1, "nmon_interval_min": 1,
    }))

    def _is_windows(h):
        return (h.get("os_group") or "").lower() in ("windows", "win")

    to_enable = []        # [{hostname, interval, prev_interval, prev_enabled}]
    to_disable = []
    skipped_windows = []
    unchanged = []

    for h in all_hosts:
        hn = h["hostname"]
        was = bool(h.get("nmon_enabled"))
        prev_iv = h.get("nmon_interval_min")
        want_iv = configs.get(hn)
        win = _is_windows(h)

        if want_iv is not None and win:
            skipped_windows.append(hn)
            continue

        if want_iv is not None:
            to_enable.append({
                "hostname": hn,
                "interval_min": want_iv,
                "prev_interval_min": prev_iv,
                "prev_enabled": was,
                "changed": (not was) or (prev_iv != want_iv),
            })
        elif was:
            to_disable.append(hn)
        else:
            unchanged.append(hn)

    # 依 interval 分組
    groups = {}
    for item in to_enable:
        groups.setdefault(item["interval_min"], []).append(item["hostname"])
    groups_list = [{"interval_min": k, "hosts": v, "count": len(v)}
                   for k, v in sorted(groups.items())]

    return jsonify({
        "success": True,
        "data": {
            "to_enable": to_enable,
            "to_disable": to_disable,
            "skipped_windows": skipped_windows,
            "unchanged_count": len(unchanged),
            "groups": groups_list,
        },
    })


@bp.route("/schedule", methods=["POST"])
@admin_required
def schedule_post():
    """
    body: {host_configs: [{hostname, interval_min}, ...], confirm: true}
    - 擋 Windows
    - 依 interval 分組, 每組跑一次 collect_nmon.yml
    - to_disable 跑 remove_nmon.yml
    - 支援舊格式 {interval_min, hostnames}
    """
    body = request.get_json(silent=True) or {}
    if not body.get("confirm"):
        return jsonify({"success": False, "error": "confirm=true required (preview first)"}), 400

    configs = _parse_host_configs(body)

    hosts_col = get_collection("hosts")
    all_hosts = list(hosts_col.find({}, {
        "_id": 0, "hostname": 1, "os_group": 1, "nmon_enabled": 1,
    }))

    def _is_windows(h):
        return (h.get("os_group") or "").lower() in ("windows", "win")

    to_enable = {}   # hostname → interval
    to_disable = []
    skipped_windows = []
    now_ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    for h in all_hosts:
        hn = h["hostname"]
        was = bool(h.get("nmon_enabled"))
        want_iv = configs.get(hn)
        win = _is_windows(h)
        if want_iv is not None and win:
            skipped_windows.append(hn)
            continue
        if want_iv is not None:
            hosts_col.update_one({"hostname": hn}, {"$set": {
                "nmon_enabled": True,
                "nmon_interval_min": want_iv,
                "nmon_deployed_at": now_ts,
            }})
            to_enable[hn] = want_iv
        elif was:
            hosts_col.update_one({"hostname": hn}, {"$set": {
                "nmon_enabled": False,
                "nmon_removed_at": now_ts,
            }})
            to_disable.append(hn)

    # 全域 interval 取「最常用那個」當預設 (留供以後新主機預設)
    if to_enable:
        from collections import Counter
        most_common = Counter(to_enable.values()).most_common(1)[0][0]
        settings_col = get_collection("settings")
        settings_col.update_one(
            {"key": "nmon_interval_min"},
            {"$set": {"key": "nmon_interval_min", "value": most_common, "updated_at": now_ts}},
            upsert=True,
        )

    logdir = os.path.join(INSPECTION_HOME, "logs")
    os.makedirs(logdir, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""

    deploy_logs = []

    # 依 interval 分組, 每組一個 ansible playbook run
    from collections import defaultdict
    groups = defaultdict(list)
    for hn, iv in to_enable.items():
        groups[iv].append(hn)

    for iv, hosts in sorted(groups.items()):
        log_name = f"nmon_schedule_deploy_{iv}min_{stamp}.log"
        log_path = os.path.join(logdir, log_name)
        limit_arg = ":".join(hosts)
        deploy_cmd = (f"cd {ANSIBLE_DIR} && ansible-playbook -i inventory/hosts.yml {vault_arg} "
                      f"playbooks/collect_nmon.yml --limit '{limit_arg}' "
                      f"-e nmon_interval_min={iv}")
        try:
            subprocess.Popen(["bash", "-c", f"nohup bash -c '{deploy_cmd}' > {log_path} 2>&1 &"],
                             close_fds=True)
            deploy_logs.append({"interval_min": iv, "hosts": hosts, "log": log_name})
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

    # 訊息
    msg_parts = []
    if deploy_logs:
        per_iv = ", ".join(f"{g['interval_min']}min x {len(g['hosts'])} 台" for g in deploy_logs)
        msg_parts.append(f"部署 {sum(len(g['hosts']) for g in deploy_logs)} 台 ({per_iv})")
    if to_disable:
        msg_parts.append(f"移除 {len(to_disable)} 台 cron (歷史資料保留)")
    if skipped_windows:
        msg_parts.append(f"跳過 {len(skipped_windows)} 台 Windows")
    if not msg_parts:
        msg_parts.append("無變更")

    return jsonify({
        "success": True,
        "data": {
            "enabled_count": sum(len(g["hosts"]) for g in deploy_logs),
            "groups": deploy_logs,
            "to_disable": to_disable,
            "skipped_windows": skipped_windows,
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
