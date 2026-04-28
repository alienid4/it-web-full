#!/usr/bin/env python3
"""
系統聯通圖 demo 種子資料 — v2 真主機版 (v3.14.0.1+)

從 hosts collection 撈真實 hostname,分配到 demo 業務系統,讓拓撲圖跟 221 環境貼合。
4 台真主機 (secansible/secclient1/sec9c2/WIN-7L4JNM4P2KN) 對應到 7 個業務系統:
  - INSPECTION-WEB / INSPECTION-DB → secansible
  - LINUX-RHEL → secclient1
  - LINUX-DEBIAN → sec9c2
  - WIN-SVR → WIN-7L4JNM4P2KN
  - AD-LDAP / DNS-INTERNAL → 外部, 無 host_ref

連線是手動模擬 (Stage 1 demo),Stage 3 跑 ss -tunp 才會出真實連線。

用法:
    python3 seed_dependency_demo.py        # 灌種子
    python3 seed_dependency_demo.py --wipe # 先清空再灌
"""
import os
import sys
import argparse
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
WEBAPP = os.path.normpath(os.path.join(HERE, "..", "webapp"))
sys.path.insert(0, WEBAPP)

from services.mongo_service import get_collection, get_hosts_col
from services import dependency_service


def build_demo(host_map):
    """根據 hosts collection 動態建構 demo 系統 + 邊
    host_map: {hostname: {ip, os, ...}}
    """
    # 偵測 4 台預期主機 (沒抓到就用空 list)
    rhel_hosts = [h for h, info in host_map.items()
                  if info.get("os", "").lower().startswith(("rocky", "rhel", "red hat", "centos"))
                  and h not in ("secansible",)]
    debian_hosts = [h for h, info in host_map.items()
                    if info.get("os", "").lower().startswith(("debian", "ubuntu"))]
    win_hosts = [h for h, info in host_map.items()
                 if info.get("os", "").lower().startswith("windows")]
    has_secansible = "secansible" in host_map

    systems = []
    if has_secansible:
        systems.append({
            "system_id": "INSPECTION-WEB",
            "display_name": "巡檢系統 Web",
            "tier": "A", "category": "AP",
            "owner": "Alienlee",
            "host_refs": ["secansible"],
            "description": "Flask + Gunicorn 跑在 secansible (221), 提供巡檢 UI / API",
        })
        systems.append({
            "system_id": "INSPECTION-DB",
            "display_name": "巡檢資料庫",
            "tier": "A", "category": "DB",
            "owner": "Alienlee",
            "host_refs": ["secansible"],
            "description": "MongoDB 容器 (Podman) 跑在 secansible 27017",
        })
    if rhel_hosts:
        systems.append({
            "system_id": "LINUX-RHEL",
            "display_name": "RHEL 系列受控主機",
            "tier": "B", "category": "Infra",
            "owner": "IT 系統組",
            "host_refs": rhel_hosts,
            "description": "Rocky Linux / RHEL 受監控群組",
        })
    if debian_hosts:
        systems.append({
            "system_id": "LINUX-DEBIAN",
            "display_name": "Debian 系列受控主機",
            "tier": "B", "category": "Infra",
            "owner": "IT 系統組",
            "host_refs": debian_hosts,
            "description": "Debian / Ubuntu 受監控群組",
        })
    if win_hosts:
        systems.append({
            "system_id": "WIN-SVR",
            "display_name": "Windows 受控主機",
            "tier": "B", "category": "Infra",
            "owner": "IT 系統組",
            "host_refs": win_hosts,
            "description": "Windows Server 受監控群組",
        })

    # 外部系統 (無 host_ref)
    systems.append({
        "system_id": "AD-LDAP",
        "display_name": "AD/LDAP 認證",
        "tier": "A", "category": "External",
        "owner": "資安部",
        "host_refs": [],
        "external": True,
        "description": "全公司單一登入認證來源 (示意,實際 demo 環境無)",
    })
    systems.append({
        "system_id": "DNS-INTERNAL",
        "display_name": "內部 DNS",
        "tier": "C", "category": "External",
        "owner": "IT 系統組",
        "host_refs": [],
        "external": True,
        "description": "內網 DNS 解析 (示意)",
    })

    # ── 關係 (手動模擬;Stage 3 ss-tunp 會自動補真實連線) ──
    relations = []
    sys_ids = {s["system_id"] for s in systems}

    def add(fs, ts, rtype, proto, port, desc):
        if fs in sys_ids and ts in sys_ids:
            relations.append((fs, ts, rtype, proto, port, desc))

    # 巡檢系統內部
    add("INSPECTION-WEB", "INSPECTION-DB", "db", "TCP", 27017, "Flask 連 MongoDB")
    # Ansible SSH 連受控主機
    add("INSPECTION-WEB", "LINUX-RHEL",    "network", "TCP", 22, "Ansible SSH 推 playbook")
    add("INSPECTION-WEB", "LINUX-DEBIAN",  "network", "TCP", 22, "Ansible SSH 推 playbook")
    add("INSPECTION-WEB", "WIN-SVR",       "network", "TCP", 22, "Ansible SSH 推 playbook (Win 走 OpenSSH)")
    # 受控主機 → AD/DNS
    add("LINUX-RHEL",   "AD-LDAP",      "network", "TCP", 389, "LDAP 認證")
    add("LINUX-DEBIAN", "AD-LDAP",      "network", "TCP", 389, "LDAP 認證")
    add("WIN-SVR",      "AD-LDAP",      "network", "TCP", 389, "AD 加入網域")
    add("LINUX-RHEL",   "DNS-INTERNAL", "network", "UDP", 53,  "DNS 查詢")
    add("LINUX-DEBIAN", "DNS-INTERNAL", "network", "UDP", 53,  "DNS 查詢")
    add("WIN-SVR",      "DNS-INTERNAL", "network", "UDP", 53,  "DNS 查詢")
    add("INSPECTION-WEB", "DNS-INTERNAL", "network", "UDP", 53, "DNS 查詢")

    return systems, relations


def wipe():
    sys_col = get_collection("dependency_systems")
    rel_col = get_collection("dependency_relations")
    s = sys_col.delete_many({}).deleted_count
    r = rel_col.delete_many({}).deleted_count
    print(f"[wipe] dependency_systems 清掉 {s} 筆, dependency_relations 清掉 {r} 筆")


def seed():
    dependency_service.ensure_indexes()
    hosts_col = get_hosts_col()
    host_map = {h["hostname"]: h for h in hosts_col.find({}, {"_id": 0})}
    print(f"[seed] 從 hosts collection 撈到 {len(host_map)} 台真主機: {sorted(host_map.keys())}")

    systems, relations = build_demo(host_map)
    sys_col = get_collection("dependency_systems")
    rel_col = get_collection("dependency_relations")
    now = datetime.utcnow()

    sys_inserted, sys_skipped = 0, 0
    for s in systems:
        if sys_col.find_one({"system_id": s["system_id"]}):
            sys_skipped += 1
            continue
        doc = dict(s)
        doc.setdefault("external", False)
        doc.setdefault("metadata", {})
        doc["created_at"] = now
        doc["updated_at"] = now
        doc["created_by"] = "seed_demo_v2"
        sys_col.insert_one(doc)
        sys_inserted += 1

    rel_inserted, rel_skipped = 0, 0
    for fs, ts, rtype, proto, port, desc in relations:
        if rel_col.find_one({"from_system": fs, "to_system": ts, "port": port}):
            rel_skipped += 1
            continue
        rel_col.insert_one({
            "from_system": fs, "to_system": ts,
            "relation_type": rtype, "protocol": proto, "port": port,
            "source": "manual", "evidence": {},
            "description": desc,
            "manual_confirmed": True,
            "created_at": now, "updated_at": now,
            "created_by": "seed_demo_v2",
        })
        rel_inserted += 1

    print(f"[seed] 系統節點: 新增 {sys_inserted} / 跳過 {sys_skipped} (共 {len(systems)} 個)")
    print(f"[seed] 依賴邊  : 新增 {rel_inserted} / 跳過 {rel_skipped} (共 {len(relations)} 條)")
    print("[seed] 主機分配:")
    for s in systems:
        if s.get("host_refs"):
            print(f"        {s['system_id']:<18} → {s['host_refs']}")
    print("[seed] 完成,開啟 https://<host>/dependencies 查看")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--wipe", action="store_true")
    args = p.parse_args()
    if args.wipe:
        wipe()
    seed()


if __name__ == "__main__":
    main()
