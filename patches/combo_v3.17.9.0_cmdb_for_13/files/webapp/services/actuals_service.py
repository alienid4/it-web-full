"""
actuals_service.py - 真實偵測值 (ansible facts) vs 資產表填寫 對照
v3.17.9.0+

來源:
  - 資產表填寫: hosts.{os, ip, hostname}
  - 真實偵測:   inspections.{os, ip, hostname} (最新一筆)

衝突顯示原則:
  - 不自動覆蓋 hosts (人填值是責任歸屬)
  - 加標記 _actuals dict 給前端判斷顯示 ⚠️
  - 提供「一鍵採用」API
"""
from services.mongo_service import get_collection


# 哪些欄位要對照
COMPARE_FIELDS = ["os", "ip", "hostname"]


def get_actuals_map():
    """回傳 {hostname: {os, ip, hostname}} (最新一筆 inspection 偵測值)"""
    col = get_collection("inspections")
    pipeline = [
        {"$sort": {"run_date": -1, "run_time": -1}},
        {"$group": {"_id": "$hostname", "doc": {"$first": "$$ROOT"}}},
        {"$replaceRoot": {"newRoot": "$doc"}},
        {"$project": {"_id": 0, "hostname": 1, "ip": 1, "os": 1, "run_date": 1}},
    ]
    return {d["hostname"]: d for d in col.aggregate(pipeline) if d.get("hostname")}


def annotate_host(host, actuals_map=None):
    """為單一 host 加 _actuals + _mismatches 欄位.
    回傳: 修改後的 host dict (in-place 也會改)
    """
    if actuals_map is None:
        actuals_map = get_actuals_map()
    hn = host.get("hostname")
    actual = actuals_map.get(hn) or {}
    actuals = {}
    mismatches = []
    for f in COMPARE_FIELDS:
        a = actual.get(f)
        u = host.get(f)
        if a:
            actuals[f] = a
            # 不一致才標 mismatch (兩值都有 + 不同)
            if u and a and str(u).strip() != str(a).strip():
                mismatches.append({"field": f, "user": u, "actual": a})
    host["_actuals"] = actuals
    host["_mismatches"] = mismatches
    host["_last_inspection_date"] = actual.get("run_date", "")
    return host


def annotate_hosts(hosts):
    """批次標記多筆 hosts (一次撈 actuals_map 比較快)"""
    actuals_map = get_actuals_map()
    for h in hosts:
        annotate_host(h, actuals_map)
    return hosts


def adopt_actual(hostname, field):
    """把實際偵測值寫進 hosts (一鍵採用)"""
    if field not in COMPARE_FIELDS:
        return False, f"不支援欄位 {field}"
    actuals_map = get_actuals_map()
    actual = actuals_map.get(hostname) or {}
    new_value = actual.get(field)
    if not new_value:
        return False, f"沒有 {field} 偵測值可採用"
    col = get_collection("hosts")
    if not col.find_one({"hostname": hostname}):
        return False, f"主機 {hostname} 不存在"
    col.update_one({"hostname": hostname}, {"$set": {field: new_value}})
    return True, f"{hostname}.{field} 已採用實際值: {new_value}"
