"""
change_log.py - 主機變更歷史 (P6 of CMDB 整合)
紀錄 hosts collection 的 CRUD 行為, timeline 顯示
"""
from datetime import datetime
from services.mongo_service import get_collection


def _now():
    return datetime.now().isoformat()


def ensure_indexes():
    col = get_collection("change_log")
    col.create_index([("hostname", 1), ("when", -1)])
    col.create_index([("when", -1)])


def record(hostname, action, who, before=None, after=None, detail=""):
    """記錄一筆變更
    action: create / update / delete / merge / scan
    """
    col = get_collection("change_log")
    doc = {
        "hostname": hostname,
        "action": action,
        "who": who or "unknown",
        "before": before,
        "after": after,
        "when": _now(),
        "detail": detail or "",
    }
    col.insert_one(doc)
    return doc


def list_history(hostname=None, limit=200):
    """取主機歷史 (依時間倒序). hostname=None 則回全部"""
    col = get_collection("change_log")
    q = {"hostname": hostname} if hostname else {}
    docs = list(col.find(q, {"_id": 0}).sort("when", -1).limit(limit))
    return docs


def diff_dicts(before, after, ignore_keys=("updated_at", "imported_at")):
    """比對 before/after dict, 回傳變更欄位 list"""
    if not isinstance(before, dict) or not isinstance(after, dict):
        return []
    keys = set(before.keys()) | set(after.keys())
    changes = []
    for k in sorted(keys):
        if k in ignore_keys or k.startswith("_"):
            continue
        bv = before.get(k)
        av = after.get(k)
        if bv != av:
            changes.append({"field": k, "before": bv, "after": av})
    return changes
