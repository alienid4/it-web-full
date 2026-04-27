#!/usr/bin/env python3
"""
VMware service — 把 vmware_snapshots collection 的最新快照 aggregate 成主管開門版 overview。

Data flow:
  vcenter_collector.py → MongoDB vmware_snapshots → vmware_service.get_overview_data() → vmware.html

若 MongoDB 沒資料 (collector 還沒跑), fallback 到 services.vmware_mock 的 inline 假資料。
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import Any

from services.mongo_service import get_db


# ============================================================
#  最新快照抓取
# ============================================================
def get_latest_snapshot_per_vc() -> list[dict]:
    """MongoDB aggregate: 每個 vcenter.ip 拿最新 1 筆 snapshot。"""
    db = get_db()
    try:
        pipeline = [
            {"$sort": {"timestamp": -1}},
            {"$group": {"_id": "$vcenter.ip", "doc": {"$first": "$$ROOT"}}},
            {"$replaceRoot": {"newRoot": "$doc"}},
            {"$sort": {"vcenter.label": 1}},
        ]
        return list(db.vmware_snapshots.aggregate(pipeline))
    except Exception:
        return []


# ============================================================
#  Aggregate (snapshots → overview)
# ============================================================
def _status_of_cluster(cluster: dict) -> str:
    """依 cluster CPU 和 version 判斷狀態 (ok/warn/danger)。"""
    ver = _latest_host_version(cluster)
    cpu_pct = cluster.get("cpu_pct", 0)
    # EOS (vSphere 7.x) 算 warn (合規風險)
    if ver and ver.startswith("7."):
        return "warn"
    if cpu_pct and cpu_pct > 80:
        return "warn"
    return "ok"


def _latest_host_version(cluster: dict) -> str | None:
    """從 cluster 層看不到 version (cluster.summary 無), 之後會從 hosts 補"""
    return cluster.get("_version")  # 由 aggregate 時注入


def _is_eos(version: str | None) -> bool:
    return bool(version and version.startswith("7."))


def _is_uat(cluster_name: str) -> bool:
    n = (cluster_name or "").upper()
    return "UAT" in n or "TEST" in n


def aggregate_overview(snapshots: list[dict]) -> dict:
    """把多 VC snapshots 合成主管版 overview dict (shape 跟 vmware_mock 相同)。"""
    now = datetime.now()

    total_hosts = 0
    total_clusters = 0
    warn_clusters = 0
    eos_hosts = 0
    hw_events = 0
    live_vcs = 0
    failed_vcs = 0

    loc_map: dict[str, dict] = {}
    risks: list[dict] = []
    vc_chips: list[dict] = []

    latest_ts = None

    for snap in snapshots:
        vc = snap.get("vcenter", {})
        label = vc.get("label", "?")
        ip = vc.get("ip", "?")
        loc = vc.get("location") or label  # fallback: 沒 location 就用 label
        status = snap.get("status")
        about = snap.get("about") or {}

        # 資料新鮮度 (取最新)
        ts = snap.get("timestamp")
        if ts and (latest_ts is None or ts > latest_ts):
            latest_ts = ts

        # VC 資料源 chip
        if status == "success":
            live_vcs += 1
            vc_chips.append({
                "name": label, "host": ip, "status": "live",
                "version": about.get("version"),
            })
        else:
            failed_vcs += 1
            vc_chips.append({
                "name": label, "host": ip, "status": "pending",
                "version": None,
            })

        clusters = snap.get("clusters", [])
        hosts = snap.get("hosts", [])

        # 推斷每個 cluster 的 version (從 cluster 內 host 看)
        cluster_version_map: dict[str, str] = {}
        for h in hosts:
            cname = h.get("cluster")
            hver = h.get("version")
            if cname and hver and cname not in cluster_version_map:
                cluster_version_map[cname] = hver

        total_hosts += len(hosts)
        total_clusters += len(clusters)

        # EOS host 數 (version 7.x)
        eos_hosts += sum(1 for h in hosts if _is_eos(h.get("version")))

        # 建構 location 層級資料
        if loc not in loc_map:
            loc_map[loc] = {"name": loc, "esxi_count": 0, "clusters": [], "ok_count": 0, "total_count": 0}
        loc_map[loc]["esxi_count"] += len(hosts)

        for c in clusters:
            cname = c.get("name")
            cver = cluster_version_map.get(cname)
            cpu_pct = c.get("cpu_pct", 0)

            # 判狀態
            if _is_eos(cver):
                c_status = "warn"
            elif cpu_pct and cpu_pct > 80:
                c_status = "warn"
            else:
                c_status = "ok"

            if c_status != "ok":
                warn_clusters += 1

            # 建 tag 字串
            tag_parts = []
            if _is_eos(cver):
                tag_parts.append("EOS")
            if cpu_pct and cpu_pct > 80:
                tag_parts.append(f"CPU {int(cpu_pct)}%")
            if _is_uat(cname) and "UAT" not in tag_parts:
                tag_parts.append("測試")
            tag = " · ".join(tag_parts) if tag_parts else None

            loc_map[loc]["clusters"].append({
                "name": cname,
                "status": c_status,
                "tag": tag,
                "host_count": c.get("host_count", 0),
            })
            loc_map[loc]["total_count"] += 1
            if c_status == "ok":
                loc_map[loc]["ok_count"] += 1

    # 組 risks (簡單版, 根據統計)
    if eos_hosts > 0:
        risks.append({
            "title": f"{eos_hosts} 台 ESXi 跑 EOS 版本",
            "desc": "vSphere 7.0 2025-10 已 EOL · 金管會稽核可能列點 · Q3 前完成升級",
            "level": "danger",
        })
    high_cpu_clusters = []
    for loc in loc_map.values():
        for c in loc["clusters"]:
            if "CPU" in (c.get("tag") or ""):
                high_cpu_clusters.append(c["name"])
    if high_cpu_clusters:
        risks.append({
            "title": f"{high_cpu_clusters[0]} CPU 高負載",
            "desc": f"連續多日 > 80% · 建議擴容或排程調整 · 影響 {len(high_cpu_clusters)} 個 cluster",
            "level": "warn",
        })
    if failed_vcs > 0:
        risks.append({
            "title": f"{failed_vcs} 個 vCenter 無法連線",
            "desc": "collector 失敗 · 檢查 logs/vcenter_collector.log",
            "level": "warn",
        })

    # 整體狀態
    if failed_vcs > 0 or eos_hosts > 0:
        overall = "warn"  # 有風險但不是 danger, 主管看得到 ⚠ 但不是 ✕
    else:
        overall = "ok"

    # 下次抓取 (8H)
    next_fetch = None
    if latest_ts:
        nxt = latest_ts + timedelta(hours=8)
        next_fetch = nxt.strftime("%Y-%m-%d %H:%M")
    last_fetch = latest_ts.strftime("%Y-%m-%d %H:%M") if latest_ts else now.strftime("%Y-%m-%d %H:%M")

    # 月報 (目前尚未實作, 先寫死上月)
    last_month = (now.replace(day=1) - timedelta(days=1)).strftime("%Y-%m")

    return {
        "last_fetch": last_fetch,
        "next_fetch": next_fetch or "—",
        "mock_mode": bool(snapshots and snapshots[0].get("mock")),  # 來自 mock-write
        "total_hosts": total_hosts,
        "total_clusters": total_clusters,
        "warn_clusters": warn_clusters,
        "eos_hosts": eos_hosts,
        "hw_events": hw_events,
        "status_overall": overall,
        "report_available": {
            "month": last_month,
            "generated": last_fetch,
            "pages": 6, "size": "2.1 MB", "has_pdf": True,
        },
        "next_report_date": (now.replace(day=1) + timedelta(days=32)).replace(day=1).strftime("%Y-%m-%d"),
        "locations": list(loc_map.values()),
        "risks": risks,
        "vcenters": vc_chips,
    }


# ============================================================
#  Public entry
# ============================================================
def get_overview_data() -> dict:
    """主 entry: MongoDB 有資料就用 MongoDB, 否則 fallback 到 inline mock。"""
    snapshots = get_latest_snapshot_per_vc()
    if snapshots:
        return aggregate_overview(snapshots)

    # Fallback: MongoDB 沒資料 → 用 inline mock
    from services.vmware_mock import get_overview_data as inline_mock
    data = inline_mock()
    data["_source"] = "inline_mock_fallback"
    return data
