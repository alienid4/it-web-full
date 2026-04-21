#!/usr/bin/env python3
# =========================================================
# csv_to_inventory.py
# 主機清單 CSV 轉換為 hosts_config.json
#
# 執行方式：
#   python3 csv_to_inventory.py <csv_file> [--mode skip|update]
#
# 範例：
#   python3 csv_to_inventory.py serverlist.csv
#   python3 csv_to_inventory.py serverlist.csv --mode update
#
# 模式說明：
#   skip   (預設) 已存在的主機跳過不更新
#   update          已存在的主機更新資料
#
# CSV 欄位（A~AC 共 29 欄）：
#   A  盤點單位-處別    B  盤點單位-部門    C  資產序號
#   D  資產狀態         E  群組名稱         F  APID
#   G  資產名稱         H  整體基礎架構     I  設備機型
#   J  資產用途         K  資產實體位置     L  機櫃編號
#   M  數量             N  擁有者           O  環境別
#   P  主機名稱 ★      Q  作業系統 ★      R  BIG IP/VIP
#   S  硬體編號         T  IP ★            U  保管者
#   V  使用單位         W  使用者           X  附加說明
#   Y  所屬公司         Z  完整性(I)        AA 機密性(C)
#   AB 可用性(A)        AC 申請單編號
#
# ★ = Ansible 必要欄位
# =========================================================
# 變更記錄：
#   v1.0  2026-04-08  初版
# =========================================================

import csv
import json
import sys
import os
import argparse
from datetime import datetime

# =========================================================
# 設定區
# =========================================================
INSPECTION_HOME = "/opt/inspection"
OUTPUT_FILE = f"{INSPECTION_HOME}/data/hosts_config.json"
BACKUP_DIR = f"{INSPECTION_HOME}/data/snapshots"

# 資產狀態：只有「使用中」才納入
ACTIVE_STATUS = ["使用中"]

# OS 對應表（之後新增 OS 只需在這裡加）
OS_MAP = {
    # Windows
    "Windows Server 2019": "windows",
    "Windows Server 2016": "windows",
    "Windows Server 2012": "windows",
    "Windows Server 2012 R2": "windows",
    # RHEL / CentOS
    "Red Hat Enterprise Linux": "rhel",
    "RHEL": "rhel",
    "CentOS": "centos",
    "CentOS Linux": "centos",
    "Rocky Linux": "rocky",
    # Debian / Ubuntu
    "Debian": "debian",
    "Ubuntu": "ubuntu",
    # AIX
    "AIX": "aix",
    "AIX 7.1": "aix",
    "AIX 7.2": "aix",
    # 其他
    "HP-UX": "hpux",
    "Solaris": "solaris",
}

# CSV 欄位對應（欄位名稱 → index，0-based）
# A=0, B=1, ... Z=25, AA=26, AB=27, AC=28
COL = {
    "division":       0,   # A 盤點單位-處別
    "department":     1,   # B 盤點單位-部門
    "asset_seq":      2,   # C 資產序號
    "status":         3,   # D 資產狀態
    "group_name":     4,   # E 群組名稱（公司內部，非 Ansible group）
    "apid":           5,   # F APID
    "asset_name":     6,   # G 資產名稱
    "infra":          7,   # H 整體基礎架構
    "device_type":    8,   # I 設備機型
    "asset_usage":    9,   # J 資產用途
    "location":       10,  # K 資產實體位置
    "rack":           11,  # L 機櫃編號
    "quantity":       12,  # M 數量
    "owner":          13,  # N 擁有者
    "environment":    14,  # O 環境別
    "hostname":       15,  # P 主機名稱 ★
    "os":             16,  # Q 作業系統 ★
    "bigip":          17,  # R BIG IP/VIP
    "hw_serial":      18,  # S 硬體編號
    "ip":             19,  # T IP ★
    "custodian":      20,  # U 保管者
    "user_unit":      21,  # V 使用單位
    "user":           22,  # W 使用者
    "note":           23,  # X 附加說明
    "company":        24,  # Y 所屬公司
    "integrity":      25,  # Z 完整性(I)
    "confidentiality":26,  # AA 機密性(C)
    "availability":   27,  # AB 可用性(A)
    "request_no":     28,  # AC 申請單編號
}

# =========================================================
# 工具函式
# =========================================================
def log_info(msg):  print(f"[INFO]  {msg}")
def log_warn(msg):  print(f"[WARN]  {msg}")
def log_error(msg): print(f"[ERROR] {msg}")
def log_stage(msg): print(f"\n{'='*10} {msg} {'='*10}")

def get_col(row, key):
    """安全取得欄位值，超出範圍或空值回傳空字串"""
    idx = COL.get(key, -1)
    if idx < 0 or idx >= len(row):
        return ""
    return row[idx].strip()

def detect_os_group(os_str):
    """對應 OS 字串到 os_group，找不到回傳 unknown"""
    if not os_str:
        return "unknown"
    for key, group in OS_MAP.items():
        if key.lower() in os_str.lower():
            return group
    return "unknown"

def backup_existing(output_file, backup_dir):
    """備份現有的 hosts_config.json"""
    if not os.path.exists(output_file):
        return None
    os.makedirs(backup_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = f"{backup_dir}/hosts_config_{timestamp}.json"
    import shutil
    shutil.copy2(output_file, backup_file)
    log_info(f"備份完成 → {backup_file}")
    return backup_file

# =========================================================
# 主要功能
# =========================================================
def load_existing(output_file):
    """載入現有的 hosts_config.json"""
    if not os.path.exists(output_file):
        return {"hosts": [], "last_updated": "", "total": 0}
    with open(output_file, "r", encoding="utf-8") as f:
        return json.load(f)

def parse_csv(csv_file):
    """讀取 CSV，回傳所有 row"""
    rows = []
    with open(csv_file, "r", encoding="utf-8-sig") as f:
        reader = csv.reader(f)
        headers = next(reader, None)  # 跳過 header
        for row in reader:
            if any(cell.strip() for cell in row):  # 跳過空行
                rows.append(row)
    return rows

def process_row(row):
    """將一列 CSV 轉換為 host dict"""
    return {
        "hostname":        get_col(row, "hostname"),
        "ip":              get_col(row, "ip"),
        "os":              get_col(row, "os"),
        "os_group":        detect_os_group(get_col(row, "os")),
        "status":          get_col(row, "status"),
        "environment":     get_col(row, "environment"),
        "group":           None,          # 後台拖拉設定
        "asset_seq":       get_col(row, "asset_seq"),
        "asset_name":      get_col(row, "asset_name"),
        "division":        get_col(row, "division"),
        "department":      get_col(row, "department"),
        "group_name":      get_col(row, "group_name"),
        "apid":            get_col(row, "apid"),
        "infra":           get_col(row, "infra"),
        "device_type":     get_col(row, "device_type"),
        "asset_usage":     get_col(row, "asset_usage"),
        "location":        get_col(row, "location"),
        "owner":           get_col(row, "owner"),
        "custodian":       get_col(row, "custodian"),
        "user_unit":       get_col(row, "user_unit"),
        "user":            get_col(row, "user"),
        "note":            get_col(row, "note"),
        "company":         get_col(row, "company"),
        "integrity":       get_col(row, "integrity"),
        "confidentiality": get_col(row, "confidentiality"),
        "availability":    get_col(row, "availability"),
        "request_no":      get_col(row, "request_no"),
        "bigip":           get_col(row, "bigip"),
        "has_python":      True,          # AIX 會在後面設為 False
        "imported_at":     datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    }

def validate_host(host):
    """驗證必要欄位，回傳錯誤訊息列表"""
    errors = []
    if not host["hostname"]:
        errors.append("缺少主機名稱（P欄）")
    if not host["ip"]:
        errors.append("缺少 IP（T欄）")
    if not host["os"]:
        errors.append("缺少作業系統（Q欄）")
    if host["os_group"] == "unknown":
        errors.append(f"OS 無法對應：{host['os']}（請更新 OS_MAP）")
    return errors

def main():
    parser = argparse.ArgumentParser(description="主機清單 CSV 轉換工具")
    parser.add_argument("csv_file", help="CSV 檔案路徑")
    parser.add_argument("--mode", choices=["skip", "update"],
                        default="skip",
                        help="已存在主機的處理方式（skip/update，預設 skip）")
    parser.add_argument("--output", default=OUTPUT_FILE,
                        help=f"輸出檔案路徑（預設：{OUTPUT_FILE}）")
    args = parser.parse_args()

    log_stage("主機清單 CSV 轉換工具 v1.0")
    log_info(f"CSV 檔案：{args.csv_file}")
    log_info(f"輸出檔案：{args.output}")
    log_info(f"模式：{args.mode}")

    # 檢查 CSV 是否存在
    if not os.path.exists(args.csv_file):
        log_error(f"找不到 CSV 檔案：{args.csv_file}")
        sys.exit(1)

    # 備份現有檔案
    log_stage("備份現有設定")
    backup_existing(args.output, BACKUP_DIR)

    # 載入現有資料
    existing_data = load_existing(args.output)
    existing_hosts = {h["hostname"]: h for h in existing_data.get("hosts", [])}

    # 讀取 CSV
    log_stage("讀取 CSV")
    rows = parse_csv(args.csv_file)
    log_info(f"共讀取 {len(rows)} 筆資料")

    # 統計
    stats = {
        "total":    len(rows),
        "active":   0,
        "excluded": 0,
        "added":    0,
        "updated":  0,
        "skipped":  0,
        "error":    0,
        "unknown_os": [],
    }

    # 處理每一筆
    log_stage("處理資料")
    for i, row in enumerate(rows, 1):
        status = get_col(row, "status")
        hostname = get_col(row, "hostname")

        # 過濾非使用中
        if status not in ACTIVE_STATUS:
            log_info(f"  [{i}] 排除（{status}）：{hostname}")
            stats["excluded"] += 1
            continue

        stats["active"] += 1
        host = process_row(row)

        # AIX 設定 has_python = False
        if host["os_group"] == "aix":
            host["has_python"] = False

        # 驗證必要欄位
        errors = validate_host(host)
        if errors:
            log_warn(f"  [{i}] 驗證失敗：{hostname} → {', '.join(errors)}")
            if host["os_group"] == "unknown":
                stats["unknown_os"].append(host["os"])
            stats["error"] += 1
            continue

        # 已存在的主機
        if hostname in existing_hosts:
            if args.mode == "skip":
                log_info(f"  [{i}] 跳過（已存在）：{hostname}")
                stats["skipped"] += 1
            else:
                # 保留後台設定的 group
                host["group"] = existing_hosts[hostname].get("group", None)
                existing_hosts[hostname] = host
                log_info(f"  [{i}] 更新：{hostname}（{host['ip']}）")
                stats["updated"] += 1
        else:
            existing_hosts[hostname] = host
            log_info(f"  [{i}] 新增：{hostname}（{host['ip']}）[{host['os_group']}]")
            stats["added"] += 1

    # 寫入 hosts_config.json
    log_stage("寫入 hosts_config.json")
    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    output_data = {
        "last_updated": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "total": len(existing_hosts),
        "hosts": list(existing_hosts.values()),
    }

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(output_data, f, ensure_ascii=False, indent=2)

    log_info(f"寫入完成：{args.output}")

    # 產出 README
    readme_path = f"{BACKUP_DIR}/csv_import_readme_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
    os.makedirs(BACKUP_DIR, exist_ok=True)
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(f"執行時間：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"CSV 來源：{args.csv_file}\n")
        f.write(f"模式：{args.mode}\n\n")
        f.write(f"統計結果：\n")
        f.write(f"  CSV 總筆數：{stats['total']}\n")
        f.write(f"  使用中：{stats['active']}\n")
        f.write(f"  排除（報廢/停用）：{stats['excluded']}\n")
        f.write(f"  新增：{stats['added']}\n")
        f.write(f"  更新：{stats['updated']}\n")
        f.write(f"  跳過：{stats['skipped']}\n")
        f.write(f"  錯誤：{stats['error']}\n")
        if stats["unknown_os"]:
            f.write(f"\n未知 OS（請更新 OS_MAP）：\n")
            for os_val in set(stats["unknown_os"]):
                f.write(f"  - {os_val}\n")
        f.write(f"\n輸出檔案：{args.output}\n")
        f.write(f"備份目錄：{BACKUP_DIR}\n")
    log_info(f"README 已寫入：{readme_path}")

    # 摘要
    log_stage("執行摘要")
    log_info(f"CSV 總筆數：{stats['total']}")
    log_info(f"使用中：{stats['active']}")
    log_info(f"排除（報廢/停用）：{stats['excluded']}")
    log_info(f"新增：{stats['added']}")
    log_info(f"更新：{stats['updated']}")
    log_info(f"跳過：{stats['skipped']}")
    if stats["error"] > 0:
        log_warn(f"錯誤：{stats['error']} 筆，請確認上方警告訊息")
    if stats["unknown_os"]:
        log_warn(f"未知 OS，請更新 OS_MAP：{list(set(stats['unknown_os']))}")
    log_info(f"hosts_config.json 主機總數：{len(existing_hosts)}")

if __name__ == "__main__":
    main()
