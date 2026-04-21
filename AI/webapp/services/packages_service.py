"""
軟體套件盤點 Service 層
Collections:
  - host_packages        : 最新快照 (一台一 doc)
  - host_packages_changes: 變更日誌 (每次 diff 產生多筆)
"""
import os
import glob
import json
from datetime import datetime
from services.mongo_service import get_db, get_collection

REPORTS_DIR = os.environ.get("INSPECTION_HOME", "/opt/inspection") + "/data/reports"


# ---------- import / diff ----------
def _normalize_pkg(row):
    """role 吐出的 list 轉 dict"""
    if not isinstance(row, list):
        return None
    return {
        "name": (row[0] if len(row) > 0 else "").strip(),
        "version": (row[1] if len(row) > 1 else "").strip(),
        "arch": (row[2] if len(row) > 2 else "").strip(),
        "install_date": (row[3] if len(row) > 3 else "").strip(),
    }


def _diff_packages(old_pkgs, new_pkgs):
    """回傳 added / removed / upgraded 三個 list"""
    def _key(p):
        return p["name"]

    old_map = {_key(p): p for p in old_pkgs or []}
    new_map = {_key(p): p for p in new_pkgs or []}

    added = [p for k, p in new_map.items() if k not in old_map]
    removed = [p for k, p in old_map.items() if k not in new_map]
    upgraded = []
    for k, np in new_map.items():
        op = old_map.get(k)
        if op and op.get("version") != np.get("version"):
            upgraded.append({
                "name": np["name"],
                "old_version": op.get("version"),
                "new_version": np.get("version"),
            })
    return added, removed, upgraded


def import_packages_from_reports():
    """
    掃 data/reports/packages_*.json → upsert host_packages
    同時 diff 舊快照，寫入 host_packages_changes
    回傳 summary dict
    """
    db = get_db()
    col_pkg = db["host_packages"]
    col_chg = db["host_packages_changes"]

    pattern = os.path.join(REPORTS_DIR, "packages_*.json")
    files = sorted(glob.glob(pattern))

    summary = {
        "imported": 0,
        "added_total": 0,
        "removed_total": 0,
        "upgraded_total": 0,
        "failed": [],
    }

    for fp in files:
        try:
            with open(fp, encoding="utf-8") as f:
                raw = json.load(f)
            hostname = raw.get("hostname")
            if not hostname:
                continue

            new_pkgs = [_normalize_pkg(r) for r in raw.get("packages", [])]
            new_pkgs = [p for p in new_pkgs if p and p.get("name")]

            # pull previous snapshot for diff
            prev = col_pkg.find_one({"hostname": hostname}, {"packages": 1})
            prev_pkgs = prev.get("packages", []) if prev else []

            added, removed, upgraded = _diff_packages(prev_pkgs, new_pkgs)

            now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

            doc = {
                "hostname": hostname,
                "os": raw.get("os"),
                "os_family": raw.get("os_family"),
                "kernel": raw.get("kernel"),
                "pkg_manager": raw.get("pkg_manager"),
                "collected_at": raw.get("collected_at") or now,
                "imported_at": now,
                "package_count": len(new_pkgs),
                "packages": new_pkgs,
            }
            col_pkg.update_one({"hostname": hostname}, {"$set": doc}, upsert=True)
            summary["imported"] += 1

            # only write change log if it's a re-scan (prev exists) and there is actual change
            if prev and (added or removed or upgraded):
                col_chg.insert_one({
                    "hostname": hostname,
                    "changed_at": now,
                    "added": added,
                    "removed": removed,
                    "upgraded": upgraded,
                    "added_count": len(added),
                    "removed_count": len(removed),
                    "upgraded_count": len(upgraded),
                })
                summary["added_total"] += len(added)
                summary["removed_total"] += len(removed)
                summary["upgraded_total"] += len(upgraded)
        except Exception as e:
            summary["failed"].append({"file": os.path.basename(fp), "error": str(e)})

    return summary


# ---------- query ----------
def list_hosts_summary():
    """主機清單頁用: 每台一行, 套件數 + 最後更新時間"""
    col = get_collection("host_packages")
    docs = list(col.find({}, {
        "_id": 0,
        "packages": 0,  # 排除 packages (太大)
    }).sort("hostname", 1))
    return docs


def get_host_packages(hostname):
    """單台完整套件清單"""
    return get_collection("host_packages").find_one(
        {"hostname": hostname}, {"_id": 0}
    )


def search_packages(query, limit=200):
    """
    搜尋套件名, 回傳每個符合套件的主機清單+版本分布
    [{name, versions: [{version, hosts: [hostname]}], host_count}]
    """
    if not query or not query.strip():
        return []
    q = query.strip().lower()
    col = get_collection("host_packages")

    # aggregate: unwind packages, match name, group by name+version
    pipeline = [
        {"$unwind": "$packages"},
        {"$match": {"packages.name": {"$regex": q, "$options": "i"}}},
        {"$group": {
            "_id": {"name": "$packages.name", "version": "$packages.version"},
            "hosts": {"$addToSet": "$hostname"},
        }},
        {"$group": {
            "_id": "$_id.name",
            "versions": {"$push": {
                "version": "$_id.version",
                "hosts": "$hosts",
                "host_count": {"$size": "$hosts"},
            }},
            "total_hosts": {"$sum": {"$size": "$hosts"}},
        }},
        {"$project": {
            "_id": 0,
            "name": "$_id",
            "versions": 1,
            "total_hosts": 1,
            "version_count": {"$size": "$versions"},
        }},
        {"$sort": {"total_hosts": -1, "name": 1}},
        {"$limit": limit},
    ]
    return list(col.aggregate(pipeline))


def get_changes(days=30, hostname=None, limit=200):
    """變更歷史"""
    col = get_collection("host_packages_changes")
    q = {}
    if hostname:
        q["hostname"] = hostname
    cursor = col.find(q, {"_id": 0}).sort("changed_at", -1).limit(limit)
    return list(cursor)


def ensure_indexes():
    db = get_db()
    db.host_packages.create_index("hostname", unique=True)
    db.host_packages.create_index("packages.name")
    db.host_packages.create_index("os_family")
    db.host_packages_changes.create_index([("changed_at", -1)])
    db.host_packages_changes.create_index("hostname")
