"""巡檢結果 Model - MongoDB inspections collection schema"""

INSPECTION_SCHEMA = {
    "hostname": str,
    "run_id": str,         # 格式: YYYYMMDD_HHMMSS
    "run_date": str,       # 格式: YYYY-MM-DD
    "run_time": str,       # 格式: HH:MM:SS
    "overall_status": str, # ok/warn/error
    "disk": dict,          # {status, partitions: [{mount, size, used, free, percent, status}]}
    "cpu": dict,           # {status, percent, cpu_percent, mem_percent}
    "service": dict,       # {status, services: [{name, status}]}
    "account": dict,       # {status, diff, uid0_alert, accounts_added, accounts_removed}
    "error_log": dict,     # {status, count, entries: [{time, level, message}]}
    "created_at": str,
}

STATUS_PRIORITY = {"error": 3, "warn": 2, "ok": 1}


def calc_overall_status(results):
    """根據各項檢查結果計算總體狀態"""
    worst = "ok"
    for key in ["disk", "cpu", "service", "account", "error_log"]:
        s = results.get(key, {}).get("status", "ok").strip()
        if STATUS_PRIORITY.get(s, 0) > STATUS_PRIORITY.get(worst, 0):
            worst = s
    return worst
