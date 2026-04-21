#!/usr/bin/env python3
# =========================================================
# generate_inventory.py
# 從 hosts_config.json 產生 Ansible hosts.yml
#
# 執行方式：
#   python3 generate_inventory.py
#
# 產生結構：
#   兩層群組：
#   1. os_group  自動從 os_group 欄位分群（linux/aix/windows）
#   2. group     後台手動設定的自訂群組
#
# =========================================================
# 變更記錄：
#   v1.0  2026-04-08  初版
# =========================================================

import json
import yaml
import sys
import os
import shutil
from datetime import datetime

# =========================================================
# 設定區
# =========================================================
INSPECTION_HOME = "/opt/inspection"
HOSTS_CONFIG    = f"{INSPECTION_HOME}/data/hosts_config.json"
OUTPUT_INVENTORY= f"{INSPECTION_HOME}/ansible/inventory/hosts.yml"
BACKUP_DIR      = f"{INSPECTION_HOME}/data/snapshots"

# ansible-host 本機設定
SECANSIBLE = {
    "hostname":   "ansible-host",
    "ip":         "<ANSIBLE_HOST>",
    "os_group":   "rocky",
    "connection": "local",
    "group":      "management",
}

# OS group 對應（os_group → 大分類）
OS_GROUP_MAP = {
    "rocky":  "linux",
    "rhel":   "linux",
    "centos": "linux",
    "debian": "linux",
    "ubuntu": "linux",
    "aix":    "aix",
    "windows":"windows",
    "hpux":   "other",
    "solaris":"other",
    "unknown":"other",
}

# =========================================================
# 工具函式
# =========================================================
def log_info(msg):  print(f"[INFO]  {msg}")
def log_warn(msg):  print(f"[WARN]  {msg}")
def log_error(msg): print(f"[ERROR] {msg}")
def log_stage(msg): print(f"\n{'='*10} {msg} {'='*10}")

def backup_existing(output_file, backup_dir):
    if not os.path.exists(output_file):
        return None
    os.makedirs(backup_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_file = f"{backup_dir}/hosts_{timestamp}.yml"
    shutil.copy2(output_file, backup_file)
    log_info(f"備份完成 → {backup_file}")
    return backup_file

def load_hosts_config(config_file):
    if not os.path.exists(config_file):
        log_error(f"找不到 hosts_config.json：{config_file}")
        log_error("請先執行 csv_to_inventory.py 匯入主機清單")
        sys.exit(1)
    with open(config_file, "r", encoding="utf-8") as f:
        return json.load(f)

# =========================================================
# 產生 Inventory 結構
# =========================================================
def build_inventory(hosts):
    inventory = {"all": {"children": {}}}
    children = inventory["all"]["children"]

    # ── 1. os_group 大分類（linux / aix / windows / other）
    os_groups = {}
    for host in hosts:
        os_group = host.get("os_group", "unknown")
        big_group = OS_GROUP_MAP.get(os_group, "other")

        if big_group not in os_groups:
            os_groups[big_group] = {}

        # 細分 os_group 子群組（例如 linux 下再分 rocky / debian）
        if os_group not in os_groups[big_group]:
            os_groups[big_group][os_group] = {"hosts": {}}

        host_vars = build_host_vars(host)
        hostname = host["hostname"]
        os_groups[big_group][os_group]["hosts"][hostname] = host_vars

    # 加入 os_group 結構
    for big_group, sub_groups in os_groups.items():
        children[big_group] = {"children": {}}
        for sub_group, sub_data in sub_groups.items():
            children[big_group]["children"][sub_group] = sub_data

    # ── 2. 後台自訂群組（group 欄位不是 null 的主機）
    custom_groups = {}
    for host in hosts:
        group = host.get("group")
        if group:
            if group not in custom_groups:
                custom_groups[group] = {"hosts": {}}
            custom_groups[group]["hosts"][host["hostname"]] = \
                {"ansible_host": host["ip"]}

    if custom_groups:
        children["custom"] = {"children": custom_groups}

    # ── 3. 環境別群組（正式 / 測試）
    env_groups = {}
    for host in hosts:
        env = host.get("environment", "")
        if env:
            env_key = f"env_{env}"
            if env_key not in env_groups:
                env_groups[env_key] = {"hosts": {}}
            env_groups[env_key]["hosts"][host["hostname"]] = \
                {"ansible_host": host["ip"]}

    if env_groups:
        children["environments"] = {"children": env_groups}

    # ── 4. ansible-host 本機（management 群組）
    children["management"] = {
        "hosts": {
            SECANSIBLE["hostname"]: {
                "ansible_host":       SECANSIBLE["ip"],
                "ansible_connection": SECANSIBLE["connection"],
            }
        }
    }

    return inventory

def build_host_vars(host):
    """建立主機變數"""
    vars = {"ansible_host": host["ip"]}

    # AIX：不使用 Python
    if host.get("os_group") == "aix":
        vars["ansible_python_interpreter"] = "auto_silent"
        vars["has_python"] = False

    # Windows：暫不支援，標記 skip
    if host.get("os_group") == "windows":
        vars["skip"] = True
        vars["skip_reason"] = "Windows 暫不支援"

    return vars

# =========================================================
# 產出 README
# =========================================================
def write_readme(hosts, output_file, stats):
    readme_path = f"{BACKUP_DIR}/inventory_readme_{datetime.now().strftime('%Y%m%d_%H%M%S')}.txt"
    os.makedirs(BACKUP_DIR, exist_ok=True)
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(f"執行時間：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"來源：{HOSTS_CONFIG}\n")
        f.write(f"輸出：{output_file}\n\n")
        f.write(f"統計：\n")
        for k, v in stats.items():
            f.write(f"  {k}：{v}\n")
        f.write(f"\n備份目錄：{BACKUP_DIR}\n")
        f.write(f"\n還原方式：\n")
        f.write(f"  cp {BACKUP_DIR}/hosts_YYYYMMDD_HHMMSS.yml {output_file}\n")
    log_info(f"README 已寫入：{readme_path}")

# =========================================================
# 主流程
# =========================================================
def main():
    log_stage("產生 Ansible Inventory v1.0")
    log_info(f"來源：{HOSTS_CONFIG}")
    log_info(f"輸出：{OUTPUT_INVENTORY}")

    # 備份
    log_stage("備份現有 Inventory")
    backup_existing(OUTPUT_INVENTORY, BACKUP_DIR)

    # 載入 hosts_config.json
    log_stage("載入 hosts_config.json")
    config = load_hosts_config(HOSTS_CONFIG)
    all_hosts = config.get("hosts", [])
    log_info(f"共 {len(all_hosts)} 台主機")

    # 統計
    stats = {
        "主機總數": len(all_hosts),
        "linux":    sum(1 for h in all_hosts if OS_GROUP_MAP.get(h.get("os_group","")) == "linux"),
        "aix":      sum(1 for h in all_hosts if OS_GROUP_MAP.get(h.get("os_group","")) == "aix"),
        "windows":  sum(1 for h in all_hosts if OS_GROUP_MAP.get(h.get("os_group","")) == "windows"),
        "other":    sum(1 for h in all_hosts if OS_GROUP_MAP.get(h.get("os_group",""), "other") == "other"),
        "有自訂群組": sum(1 for h in all_hosts if h.get("group")),
        "正式環境":  sum(1 for h in all_hosts if h.get("environment") == "正式"),
        "測試環境":  sum(1 for h in all_hosts if h.get("environment") == "測試"),
    }

    # 顯示分布
    log_stage("主機分布")
    for k, v in stats.items():
        log_info(f"  {k}：{v}")

    # 產生 Inventory
    log_stage("產生 hosts.yml")
    inventory = build_inventory(all_hosts)

    # 寫入 YAML
    os.makedirs(os.path.dirname(OUTPUT_INVENTORY), exist_ok=True)

    # 加入檔頭說明
    header = (
        f"# Ansible Inventory - hosts.yml\n"
        f"# 自動產生，請勿手動編輯\n"
        f"# 產生時間：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        f"# 來源：{HOSTS_CONFIG}\n"
        f"# 如需修改請更新 hosts_config.json 後重新執行 generate_inventory.py\n\n"
    )

    with open(OUTPUT_INVENTORY, "w", encoding="utf-8") as f:
        f.write(header)
        yaml.dump(inventory, f,
                  allow_unicode=True,
                  default_flow_style=False,
                  sort_keys=False,
                  indent=2)

    log_info(f"寫入完成：{OUTPUT_INVENTORY}")

    # README
    write_readme(all_hosts, OUTPUT_INVENTORY, stats)

    # 摘要
    log_stage("完成")
    log_info(f"Inventory 已產生：{OUTPUT_INVENTORY}")
    log_info(f"主機總數（不含 ansible-host）：{len(all_hosts)}")
    log_warn("Windows 主機已加入但標記 skip=True（暫不支援）")
    log_warn("請執行以下指令驗證：")
    log_warn(f"ansible all -i {OUTPUT_INVENTORY} --list-hosts")

if __name__ == "__main__":
    main()
