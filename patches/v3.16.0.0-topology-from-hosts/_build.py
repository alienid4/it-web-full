#!/usr/bin/env python3
"""Build v3.16.0.0 - 拓撲圖從 hosts collection 派生"""
import os, re, shutil, sys

WORK = r"C:\Users\User\AppData\Local\Temp\v3160_dep.py"
PATCH_DIR = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.16.0.0-topology-from-hosts"

# /tmp/v3160_dep.py 在 Git Bash 是另一個位置, 找實際
for p in [r"C:\Users\User\AppData\Local\Temp\v3160_dep.py", "/tmp/v3160_dep.py"]:
    if os.path.isfile(p):
        WORK = p; break

with open(WORK, encoding="utf-8") as f:
    s = f.read()

# === 改 topology() 預設用新 function ===
old_topology = '''def topology(center=None, depth=2, limit=200, view="system"):'''
if old_topology not in s:
    print("FAIL: topology() not found"); sys.exit(1)

# 改主 topology() 入口: view=system 改用 _topology_from_hosts
old_dispatch = '''def topology(center=None, depth=2, limit=200, view="system"):
    """拓撲圖入口 - view=system|host|ip 切換不同節點型態"""
    if view == "host":
        return _topology_host(center=center, limit=limit)
    if view == "ip":
        return _topology_ip(center=center, limit=limit)
    return _topology_system(center=center, depth=depth, limit=limit)'''

# 看現實際內容 (可能換行縮排有差)
m = re.search(r"def topology\(center=None.*?\)\:[\s\S]*?return _topology_system\(.*?\)", s)
if not m:
    print("FAIL: 找不到 topology dispatch"); sys.exit(1)

new_dispatch = '''def topology(center=None, depth=2, limit=200, view="system"):
    """拓撲圖入口 - view=system|host|ip 切換不同節點型態
    v3.16.0.0+: system view 改為從 hosts collection 派生 (主機 = 節點),
    舊式從 dependency_systems 派生改名 view='legacy_system'。
    """
    if view == "host":
        return _topology_host(center=center, limit=limit)
    if view == "ip":
        return _topology_ip(center=center, limit=limit)
    if view == "legacy_system":
        return _topology_system(center=center, depth=depth, limit=limit)
    return _topology_from_hosts(center=center, limit=limit)'''

s = s[:m.start()] + new_dispatch + s[m.end():]
print("[+] topology() dispatcher 改成預設用 hosts-derived")

# === 加新 function _topology_from_hosts ===
new_func = '''


def _tier_to_letter(t):
    """金/銀/銅 → A/B/C (跟舊 system tier 字母對齊)"""
    return {"金":"A","銀":"B","銅":"C"}.get(str(t).strip(), "C")


def _topology_from_hosts(center=None, limit=200):
    """v3.16.0.0+: 拓撲節點從 hosts collection 直接派生.
    每台主機 = 一個節點 (system_id = hostname).
    外部節點: dependency_systems 內 host_refs 為空 (AD/DNS/EXT-*/UNKNOWN-*)。
    """
    hosts_col = get_collection("hosts")
    sys_col = get_collection("dependency_systems")
    rel_col = get_collection("dependency_relations")

    nodes = []
    seen_ids = set()

    # 內部節點: 每台 host 一個 node, system_id = hostname
    for h in hosts_col.find({}, {"_id": 0}):
        hn = h.get("hostname")
        if not hn or hn in seen_ids:
            continue
        seen_ids.add(hn)
        nodes.append({
            "system_id": hn,
            "display_name": h.get("system_name") or h.get("apid") or hn,
            "tier": _tier_to_letter(h.get("tier", "")),
            "category": h.get("group_name") or "Internal",
            "host_refs": [hn],
            "hostname": hn,
            "ip": h.get("ip", ""),
            "owner": h.get("owner", "") or h.get("custodian", ""),
            "description": h.get("note", "") or f"{h.get('os','')} / {h.get('device_model','')}",
            "_internal": True,
            "asset_seq": h.get("asset_seq", ""),
            "custodian": h.get("custodian", ""),
        })

    # 外部節點: dependency_systems 內 host_refs 為空 (純外部)
    for ext in sys_col.find({}, {"_id": 0}):
        sid = ext.get("system_id")
        if not sid or sid in seen_ids:
            continue
        host_refs = ext.get("host_refs") or []
        # 內部 (有 host_refs) 跳過 — 已用 hosts 派生過
        if host_refs:
            continue
        seen_ids.add(sid)
        nodes.append({
            "system_id": sid,
            "display_name": ext.get("display_name") or sid,
            "tier": ext.get("tier", "C"),
            "category": ext.get("category", "External"),
            "host_refs": [],
            "owner": ext.get("owner", ""),
            "description": ext.get("description", ""),
            "_external": True,
            "_unknown": sid.startswith("UNKNOWN-"),
        })

    # 邊: 過濾出兩端都在節點清單內的
    valid_ids = {n["system_id"] for n in nodes}
    edges = []
    for r in rel_col.find({}, {"_id": 0}):
        if r.get("from_system") in valid_ids and r.get("to_system") in valid_ids:
            edges.append({
                "from_system": r["from_system"],
                "to_system": r["to_system"],
                "relation_type": r.get("relation_type", "network"),
                "port": r.get("port"),
                "protocol": r.get("protocol", ""),
                "source": r.get("source", "manual"),
                "evidence": r.get("evidence", {}),
                "description": r.get("description", ""),
            })

    truncated = len(nodes) > limit
    return {
        "nodes": nodes[:limit],
        "edges": edges,
        "meta": {
            "node_count": len(nodes),
            "edge_count": len(edges),
            "truncated": truncated,
            "view": "hosts-derived",
        },
    }
'''

# 接到檔案最後
s = s.rstrip() + new_func + "\n"

# === 寫入 patch dir ===
out = os.path.join(PATCH_DIR, "files", "webapp", "services", "dependency_service.py")
with open(out, "w", encoding="utf-8") as f:
    f.write(s)
print(f"[+] dependency_service.py 寫入 patch ({len(s)} bytes)")

# Python 語法驗證
import ast
try:
    ast.parse(s)
    print("[+] AST 語法 OK")
except SyntaxError as e:
    print(f"[FAIL] 語法錯誤: {e}")
    sys.exit(1)
