#!/usr/bin/env python3
"""
fix_os_group.py — v3.17.12.0 一次性掃 hosts collection, 補 os_group 缺漏.

背景:
  v3.17.11.0 csv_business_system 的 import_csv 把 v3.17.10.1 的 os_parse hook
  搞丟, 結果 import 進來的主機 os_group 欄位都是空的.
  NMON 排程 (api_nmon.py) 的支援白名單只認得 rhel/rocky/centos/debian/ubuntu/
  aix/linux, 所以 UI 全部顯示「不支援 (?)」.

本工具:
  - 掃所有 hosts 文件
  - os_group 為空 / null / "unknown" → 從 os 欄位用 infer_os_group() 推
  - 同時若 os_version 為空也順便補
  - 改前先把整個 hosts collection dump 到 .bak.json (備份)
  - 印 diff + 統計

用法:
  INSPECTION_HOME=/opt/inspection python3 fix_os_group.py [--dry-run]
"""
import json
import os
import sys
from datetime import datetime

INSPECTION_HOME = os.environ.get("INSPECTION_HOME") or "/opt/inspection"
sys.path.insert(0, os.path.join(INSPECTION_HOME, "webapp"))

DRY_RUN = "--dry-run" in sys.argv


def main():
    try:
        from services.mongo_service import get_hosts_col
        from services.os_parse import parse_os, family_to_group
    except Exception as e:
        print(f"[FATAL] import 失敗: {e}", file=sys.stderr)
        print(f"        INSPECTION_HOME={INSPECTION_HOME}", file=sys.stderr)
        sys.exit(1)

    col = get_hosts_col()

    # 備份 (即使 dry-run 也備份, 反正不貴)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir = os.path.join(INSPECTION_HOME, "data", "backups")
    os.makedirs(backup_dir, exist_ok=True)
    backup_path = os.path.join(backup_dir, f"hosts_pre_os_group_fix_{ts}.json")
    all_hosts = list(col.find({}, {"_id": 0}))
    with open(backup_path, "w", encoding="utf-8") as f:
        json.dump(all_hosts, f, ensure_ascii=False, indent=2, default=str)
    print(f"[BACKUP] {len(all_hosts)} 台主機 dump → {backup_path}")

    fixed = 0
    skipped = 0
    no_change = 0

    for h in all_hosts:
        hostname = h.get("hostname", "?")
        cur_grp = (h.get("os_group") or "").strip().lower()
        cur_ver = (h.get("os_version") or "").strip()
        os_str = h.get("os", "") or ""

        need_fix_grp = cur_grp in ("", "unknown")
        need_fix_ver = not cur_ver

        if not need_fix_grp and not need_fix_ver:
            no_change += 1
            continue

        if not os_str:
            print(f"[SKIP] {hostname}: 沒有 os 字串可推, os_group={cur_grp!r}")
            skipped += 1
            continue

        fam, ver = parse_os(os_str)
        new_grp = family_to_group(fam) if need_fix_grp else cur_grp
        new_ver = ver if (need_fix_ver and ver) else cur_ver

        updates = {}
        if need_fix_grp and new_grp:
            updates["os_group"] = new_grp
        if need_fix_ver and new_ver:
            updates["os_version"] = new_ver
        if fam and fam != os_str:
            # 順便把 os 也 normalize 成 canonical family (跟 _autofill_os_fields 行為一致)
            updates.setdefault("os", fam)

        if not updates:
            print(f"[SKIP] {hostname}: 無法從 os={os_str!r} 推出 (family={fam!r})")
            skipped += 1
            continue

        diff = ", ".join(f"{k}={cur_grp if k=='os_group' else (cur_ver if k=='os_version' else os_str)!r}→{v!r}" for k, v in updates.items())
        print(f"[FIX]  {hostname}: {diff}")

        if not DRY_RUN:
            col.update_one({"hostname": hostname}, {"$set": updates})
        fixed += 1

    print(f"\n========== 統計 ==========")
    print(f"  總主機數    : {len(all_hosts)}")
    print(f"  已修正      : {fixed} {'(DRY RUN, 未真改)' if DRY_RUN else ''}")
    print(f"  無需修改    : {no_change}")
    print(f"  跳過 (無資訊): {skipped}")
    print(f"  備份位置    : {backup_path}")

    # 二次驗證: 算 NMON 支援的主機數
    if not DRY_RUN:
        SUPPORTED = ("rocky", "rhel", "centos", "debian", "ubuntu", "aix", "linux")
        nmon_supported = col.count_documents({"os_group": {"$in": list(SUPPORTED)}})
        print(f"  NMON 可勾選主機數: {nmon_supported} / {len(all_hosts)}")


if __name__ == "__main__":
    main()
