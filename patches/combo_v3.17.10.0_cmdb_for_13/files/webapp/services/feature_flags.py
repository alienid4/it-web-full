"""
Feature Flags — 模組 on/off 管理
Collection: feature_flags
Schema: {key, name, enabled: bool, description, category}
"""
from services.mongo_service import get_collection

# 5 個可關模組 (core 不列於此, 永遠開)
DEFAULT_FLAGS = [
    {"key": "audit",          "name": "帳號盤點",     "description": "/audit 頁 + admin 帳號盤點 tab"},
    {"key": "packages",       "name": "軟體盤點",     "description": "/packages 頁 + Ansible 套件收集"},
    {"key": "perf",           "name": "效能月報",     "description": "/perf 頁 + admin 效能月報管理 tab (含 nmon 採樣排程)"},
    {"key": "twgcb",          "name": "TWGCB 合規",   "description": "/twgcb 系列頁 + admin TWGCB 設定 + 合規報告"},
    {"key": "summary",        "name": "異常總結",     "description": "/summary 頁"},
    {"key": "security_audit", "name": "系統安全稽核", "description": "admin 稽核專區 + Ansible 審計"},
    {"key": "history",        "name": "歷史查詢",     "description": "/history 頁 (巡檢歷史趨勢查詢)"},
    {"key": "dependencies",   "name": "系統聯通圖",     "description": "/dependencies 頁 + admin 系統聯通圖管理 tab (vis-network 互動圖)"},
    {"key": "vmware",         "name": "VMware 管理",  "description": "/vmware 頁 + vCenter read-only 月報 / 開門檢查 (v3.12.0.0+)"},
]


def ensure_defaults():
    col = get_collection("feature_flags")
    col.create_index("key", unique=True)
    for f in DEFAULT_FLAGS:
        existing = col.find_one({"key": f["key"]})
        if not existing:
            doc = dict(f)
            doc["enabled"] = True  # 預設全開
            col.insert_one(doc)


def all_flags():
    """回 dict {key: bool} 給 context processor / before_request 用"""
    col = get_collection("feature_flags")
    out = {}
    for f in col.find({}, {"_id": 0, "key": 1, "enabled": 1}):
        out[f["key"]] = bool(f.get("enabled"))
    # 沒在 DB 裡的 key 預設 True
    for d in DEFAULT_FLAGS:
        out.setdefault(d["key"], True)
    return out


def list_flags():
    """給 admin UI 列表用 — 回完整 records"""
    col = get_collection("feature_flags")
    existing = list(col.find({}, {"_id": 0}).sort("key", 1))
    known = {f["key"] for f in existing}
    # 補未在 DB 但在 DEFAULT_FLAGS 的 (理論上 ensure_defaults 已做, 但保險)
    for d in DEFAULT_FLAGS:
        if d["key"] not in known:
            existing.append({**d, "enabled": True})
    return existing


def set_flag(key, enabled):
    """更新 flag 狀態。若 key 在 DEFAULT_FLAGS 裡但 DB 沒該筆 (舊 DB 沒跑 ensure_defaults)，自動 upsert 補齊。"""
    col = get_collection("feature_flags")
    defaults = next((d for d in DEFAULT_FLAGS if d["key"] == key), None)
    if defaults:
        # 預設 key: upsert (若 DB 沒就新建, 填 name/description)
        col.update_one(
            {"key": key},
            {
                "$set": {"enabled": bool(enabled)},
                "$setOnInsert": {
                    "name": defaults["name"],
                    "description": defaults["description"],
                },
            },
            upsert=True,
        )
        return True
    # 未定義 key: 維持原行為 (不自動建)
    r = col.update_one({"key": key}, {"$set": {"enabled": bool(enabled)}}, upsert=False)
    return r.matched_count > 0
