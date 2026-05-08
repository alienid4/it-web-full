#!/usr/bin/env python3
"""
probe_os.py — v3.17.12.0 走 ansible setup module 從目標主機**真實**抓 OS,
寫回 hosts collection.

主路徑 (vs. fix_os_group.py 從 CSV 字串解析的後援路徑):
  - 跑 `ansible all -m setup -a 'gather_subset=min'`
  - 解 ansible_distribution / ansible_distribution_version / ansible_os_family
  - 對應 → (os family canonical, os_version, os_group)
  - 寫回 hosts collection
  - 連不上的主機標記 reachable=false (但保留 CSV/手填的 os_group 不動)

用法:
  INSPECTION_HOME=/opt/inspection python3 probe_os.py [--all] [--hosts h1,h2] [--dry-run]

預設 --all (掃 inventory 裡所有主機).
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime

INSPECTION_HOME = os.environ.get("INSPECTION_HOME") or "/opt/inspection"
sys.path.insert(0, os.path.join(INSPECTION_HOME, "webapp"))

DRY_RUN = "--dry-run" in sys.argv
HOSTS_ARG = ""
for i, a in enumerate(sys.argv):
    if a == "--hosts" and i + 1 < len(sys.argv):
        HOSTS_ARG = sys.argv[i + 1]


# ansible_distribution → (canonical family, os_group)
# 注意: ansible 給的 distribution 字串是固定的 (來源: setup module),
# 不需要 fuzzy parse, 直接查表即可.
DIST_MAP = {
    "RedHat":      ("RHEL",          "rhel"),
    "CentOS":      ("CentOS",        "centos"),
    "Rocky":       ("Rocky Linux",   "rocky"),
    "AlmaLinux":   ("Rocky Linux",   "rocky"),
    "OracleLinux": ("Oracle Linux",  "rhel"),
    "Fedora":      ("Fedora",        "rhel"),
    "Debian":      ("Debian",        "debian"),
    "Ubuntu":      ("Ubuntu",        "ubuntu"),
    "AIX":         ("AIX",           "aix"),
    "Alpine":      ("Alpine",        "alpine"),
    "SLES":        ("SLES",          "sles"),
    "SUSE":        ("SLES",          "sles"),
    "openSUSE":    ("openSUSE",      "sles"),
    # Windows (巡檢系統 inventory 對 Windows 用 Administrator + winrm,
    # ansible setup 在 winrm 下也能回 ansible_distribution=Microsoft Windows)
    "Microsoft Windows": ("Windows Server", "windows"),
}


def run_ansible_setup(host_pattern):
    """跑 ansible -m setup, 回傳 dict[hostname] = facts | None"""
    inv = os.path.join(INSPECTION_HOME, "ansible", "inventory", "hosts.yml")
    if not os.path.exists(inv):
        # fallback (家裡 vs 公司路徑差異)
        for p in [
            os.path.join(INSPECTION_HOME, "ansible/inventory/hosts.yaml"),
            os.path.join(INSPECTION_HOME, "ansible/hosts.yml"),
        ]:
            if os.path.exists(p):
                inv = p
                break
    print(f"[INFO] inventory = {inv}")

    cmd = [
        "ansible", "-i", inv, host_pattern,
        "-m", "setup", "-a", "gather_subset=min",
        "--timeout=15", "-o",
    ]
    print(f"[RUN ] {' '.join(cmd)}")
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        print("[FAIL] ansible setup timeout (180s)")
        return {}

    facts = {}
    # ansible -o 一行一台: "hostname | SUCCESS => {...json...}"
    # 失敗: "hostname | UNREACHABLE => {...}"  或  "hostname | FAILED! => {...}"
    line_re = re.compile(r"^(\S+)\s*\|\s*(SUCCESS|UNREACHABLE|FAILED!?)\s*(?:=>\s*)?(\{.*\})?\s*$")
    cur_host = None
    cur_lines = []
    for line in r.stdout.splitlines():
        m = line_re.match(line)
        if m:
            # flush 前一台
            if cur_host is not None:
                _flush(facts, cur_host, cur_lines)
            cur_host = m.group(1)
            cur_status = m.group(2)
            cur_lines = [(cur_status, m.group(3) or "")]
        else:
            if cur_host is not None and cur_lines:
                cur_lines[-1] = (cur_lines[-1][0], cur_lines[-1][1] + line)
    if cur_host is not None:
        _flush(facts, cur_host, cur_lines)

    # 也 parse stderr 找 unreachable (ansible 偶爾把 fail 寫 stderr)
    if r.stderr:
        for line in r.stderr.splitlines():
            m = line_re.match(line)
            if m:
                h, st, _ = m.group(1), m.group(2), m.group(3)
                if h not in facts:
                    facts[h] = None
    return facts


def _flush(facts, host, lines):
    if not lines:
        return
    status, payload = lines[0]
    if status != "SUCCESS":
        facts[host] = None
        return
    try:
        data = json.loads(payload)
        facts[host] = data.get("ansible_facts", data)
    except Exception as e:
        print(f"[WARN] {host}: 解析 JSON 失敗 ({e}), payload 開頭: {payload[:100]!r}")
        facts[host] = None


def main():
    try:
        from services.mongo_service import get_hosts_col
    except Exception as e:
        print(f"[FATAL] import mongo_service 失敗: {e}", file=sys.stderr)
        sys.exit(1)

    col = get_hosts_col()
    pattern = HOSTS_ARG if HOSTS_ARG else "all"

    # 備份
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = os.path.join(INSPECTION_HOME, "data", "backups")
    os.makedirs(backup_dir, exist_ok=True)
    backup_path = os.path.join(backup_dir, f"hosts_pre_probe_os_{ts}.json")
    snapshot = list(col.find({}, {"_id": 0}))
    with open(backup_path, "w", encoding="utf-8") as f:
        json.dump(snapshot, f, ensure_ascii=False, indent=2, default=str)
    print(f"[BACKUP] {len(snapshot)} 台主機 → {backup_path}")

    facts_map = run_ansible_setup(pattern)
    if not facts_map:
        print("[WARN] ansible 沒回任何主機, 沒事可做.")
        return

    stats = {"reachable": 0, "unreachable": 0, "updated": 0, "no_change": 0, "unknown_dist": 0}

    for hostname, facts in facts_map.items():
        host_doc = col.find_one({"hostname": hostname}) or col.find_one({"hostname": hostname.lower()})
        if not host_doc:
            print(f"[SKIP] {hostname}: 不在 hosts collection")
            continue

        if facts is None:
            stats["unreachable"] += 1
            print(f"[OFF ] {hostname}: ansible 連不上 (SSH/sudo 不通?)")
            if not DRY_RUN:
                col.update_one(
                    {"hostname": host_doc["hostname"]},
                    {"$set": {"reachable": False, "last_probe_at": datetime.now().isoformat()}},
                )
            continue

        stats["reachable"] += 1
        dist = facts.get("ansible_distribution", "")
        ver = facts.get("ansible_distribution_version", "")
        family_grp = DIST_MAP.get(dist)
        if not family_grp:
            stats["unknown_dist"] += 1
            print(f"[?   ] {hostname}: ansible_distribution={dist!r} 不在 DIST_MAP, 加進去")
            continue

        new_family, new_grp = family_grp
        cur_os = host_doc.get("os", "")
        cur_ver = host_doc.get("os_version", "")
        cur_grp = host_doc.get("os_group", "")

        updates = {
            "reachable": True,
            "last_probe_at": datetime.now().isoformat(),
        }
        if cur_os != new_family:
            updates["os"] = new_family
        if cur_ver != ver:
            updates["os_version"] = ver
        if cur_grp != new_grp:
            updates["os_group"] = new_grp

        if len(updates) <= 2:  # 只有 reachable + last_probe_at, 等於沒實質改 OS
            stats["no_change"] += 1
            print(f"[==  ] {hostname}: {new_family} {ver} (group={new_grp}) — 無變動")
        else:
            stats["updated"] += 1
            diffs = []
            if "os" in updates:       diffs.append(f"os: {cur_os!r}→{new_family!r}")
            if "os_version" in updates: diffs.append(f"ver: {cur_ver!r}→{ver!r}")
            if "os_group" in updates:  diffs.append(f"group: {cur_grp!r}→{new_grp!r}")
            print(f"[FIX ] {hostname}: " + ", ".join(diffs))

        if not DRY_RUN:
            col.update_one({"hostname": host_doc["hostname"]}, {"$set": updates})

    print(f"\n========== 統計 ==========")
    print(f"  ansible 連得上    : {stats['reachable']}")
    print(f"  ansible 連不上    : {stats['unreachable']}")
    print(f"  寫回 (有改動)     : {stats['updated']} {'(DRY RUN, 未真改)' if DRY_RUN else ''}")
    print(f"  無變動 (本來就對) : {stats['no_change']}")
    print(f"  未知 distribution : {stats['unknown_dist']}")
    print(f"  備份位置          : {backup_path}")

    if not DRY_RUN:
        SUPPORTED = ("rocky", "rhel", "centos", "debian", "ubuntu", "aix", "linux")
        nmon_ok = col.count_documents({"os_group": {"$in": list(SUPPORTED)}})
        total = col.count_documents({})
        print(f"  NMON 可勾選主機數: {nmon_ok} / {total}")


if __name__ == "__main__":
    main()
