"""TWGCB 單台主機強化管理 API"""
from flask import Blueprint, jsonify, request
import subprocess
import json
import os
from datetime import datetime
from services.mongo_service import get_db

bp = Blueprint("api_harden", __name__)

ANSIBLE_DIR = "/opt/inspection/ansible"
VAULT_PASS = "/opt/inspection/.vault_pass"
BACKUP_BASE = "/var/backups/inspection/twgcb"

# 需要備份的設定檔清單
BACKUP_FILES = [
    "/etc/ssh/sshd_config",
    "/etc/login.defs",
    "/etc/security/pwquality.conf",
    "/etc/pam.d/system-auth",
    "/etc/pam.d/password-auth",
    "/etc/passwd",
    "/etc/shadow",
    "/etc/group",
    "/etc/gshadow",
    "/etc/sysctl.conf",
    "/etc/crontab",
    "/etc/cron.allow",
    "/etc/cron.deny",
    "/etc/audit/auditd.conf",
    "/etc/issue",
    "/etc/issue.net",
    "/etc/motd",
    "/etc/security/limits.conf",
]

BACKUP_DIRS = [
    "/etc/sysctl.d/",
    "/etc/security/limits.d/",
    "/etc/audit/rules.d/",
]


def _ansible_cmd(hostname, module, args, timeout=30):
    """執行 Ansible ad-hoc 指令"""
    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""
    cmd = f'cd {ANSIBLE_DIR} && ansible {hostname} -i inventory/hosts.yml -m {module} -a "{args}" {vault_arg}'
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return result.returncode == 0, result.stdout + result.stderr
    except subprocess.TimeoutExpired:
        return False, "超時"
    except Exception as e:
        return False, str(e)


@bp.route("/api/harden/backup/full", methods=["POST"])
def full_backup():
    """一鍵全備份：目標主機 local + ansible-host 雙份"""
    if not request.is_json:
        return jsonify({"success": False, "error": "需要 JSON"}), 400

    hostname = request.json.get("hostname")
    if not hostname:
        return jsonify({"success": False, "error": "缺少 hostname"}), 400

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    local_dir = f"/var/backups/inspection/twgcb/{ts}_full"
    mgmt_dir = f"{BACKUP_BASE}/{hostname}/{ts}_full"

    # Step 1: 在目標主機上建立備份目錄並備份
    files_str = " ".join(BACKUP_FILES)
    dirs_str = " ".join(BACKUP_DIRS)

    backup_script = f"""
mkdir -p {local_dir}
# 備份檔案
for f in {files_str}; do
    if [ -f "$f" ]; then
        dir={local_dir}$(dirname $f)
        mkdir -p "$dir"
        cp -p "$f" "$dir/" 2>/dev/null
    fi
done
# 備份目錄
for d in {dirs_str}; do
    if [ -d "$d" ]; then
        dir={local_dir}$d
        mkdir -p "$dir"
        cp -rp "$d"* "$dir/" 2>/dev/null
    fi
done
# 寫備份資訊
cat > {local_dir}/backup_info.json << INFOEOF
{{"timestamp":"{ts}","type":"full","hostname":"$(hostname)","files_count":"$(find {local_dir} -type f | wc -l)"}}
INFOEOF
# 打包
cd {local_dir} && tar czf {local_dir}.tar.gz -C {local_dir} . 2>/dev/null
echo "LOCAL_BACKUP_OK"
"""

    ok, output = _ansible_cmd(hostname, "shell", backup_script.replace('"', '\\"'), timeout=60)

    if not ok or "LOCAL_BACKUP_OK" not in output:
        return jsonify({"success": False, "error": "目標主機 local 備份失敗", "output": output[-500:]}), 500

    # Step 2: Fetch 備份到 ansible-host
    os.makedirs(mgmt_dir, exist_ok=True)
    fetch_cmd = f'cd {ANSIBLE_DIR} && ansible {hostname} -i inventory/hosts.yml -m fetch -a "src={local_dir}.tar.gz dest={mgmt_dir}/backup.tar.gz flat=yes"'
    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""
    fetch_cmd += f" {vault_arg}"

    try:
        result = subprocess.run(fetch_cmd, shell=True, capture_output=True, text=True, timeout=60)
        fetch_ok = result.returncode == 0
    except Exception:
        fetch_ok = False

    # 解壓到管理主機
    if fetch_ok and os.path.exists(f"{mgmt_dir}/backup.tar.gz"):
        subprocess.run(f"cd {mgmt_dir} && tar xzf backup.tar.gz", shell=True, timeout=30)

    # 記錄到 MongoDB
    db = get_db()
    db.twgcb_backups.insert_one({
        "hostname": hostname,
        "timestamp": ts,
        "type": "full",
        "local_path": f"{local_dir}.tar.gz",
        "mgmt_path": f"{mgmt_dir}/backup.tar.gz",
        "local_ok": True,
        "mgmt_ok": fetch_ok,
        "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    })

    return jsonify({
        "success": True,
        "message": f"備份完成（local: ✓, ansible-host: {'✓' if fetch_ok else '✗'}）",
        "backup_id": ts,
        "local_path": f"{local_dir}.tar.gz",
        "mgmt_path": f"{mgmt_dir}/backup.tar.gz" if fetch_ok else None
    })


@bp.route("/api/harden/backup/item", methods=["POST"])
def item_backup():
    """單項次備份：只備份即將修改的檔案"""
    if not request.is_json:
        return jsonify({"success": False, "error": "需要 JSON"}), 400

    hostname = request.json.get("hostname")
    check_id = request.json.get("check_id")
    files = request.json.get("files", [])

    if not hostname or not check_id:
        return jsonify({"success": False, "error": "缺少 hostname/check_id"}), 400

    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    local_dir = f"/var/backups/inspection/twgcb/{ts}_{check_id}"

    files_str = " ".join(files) if files else ""
    backup_script = f"""
mkdir -p {local_dir}
for f in {files_str}; do
    if [ -f "$f" ]; then
        dir={local_dir}$(dirname $f)
        mkdir -p "$dir"
        cp -p "$f" "$dir/"
    fi
done
echo "ITEM_BACKUP_OK"
"""

    ok, output = _ansible_cmd(hostname, "shell", backup_script.replace('"', '\\"'), timeout=30)

    if ok and "ITEM_BACKUP_OK" in output:
        # 也 fetch 到管理主機
        mgmt_dir = f"{BACKUP_BASE}/{hostname}/{ts}_{check_id}"
        os.makedirs(mgmt_dir, exist_ok=True)

        db = get_db()
        db.twgcb_backups.insert_one({
            "hostname": hostname,
            "timestamp": ts,
            "type": "item",
            "check_id": check_id,
            "files": files,
            "local_path": local_dir,
            "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        })

        return jsonify({"success": True, "message": f"{check_id} 備份完成", "backup_id": ts})

    return jsonify({"success": False, "error": "單項備份失敗", "output": output[-300:]}), 500


@bp.route("/api/harden/backups/<hostname>", methods=["GET"])
def list_backups(hostname):
    """列出主機的備份紀錄"""
    db = get_db()
    backups = list(db.twgcb_backups.find(
        {"hostname": hostname}, {"_id": 0}
    ).sort("timestamp", -1).limit(20))
    return jsonify({"success": True, "data": backups})


@bp.route("/api/harden/restore", methods=["POST"])
def restore_backup():
    """還原備份"""
    if not request.is_json:
        return jsonify({"success": False, "error": "需要 JSON"}), 400

    hostname = request.json.get("hostname")
    backup_id = request.json.get("backup_id")

    if not hostname or not backup_id:
        return jsonify({"success": False, "error": "缺少 hostname/backup_id"}), 400

    db = get_db()
    backup = db.twgcb_backups.find_one({"hostname": hostname, "timestamp": backup_id})
    if not backup:
        return jsonify({"success": False, "error": "找不到備份紀錄"}), 404

    local_path = backup.get("local_path", "")

    if backup.get("type") == "full" and local_path.endswith(".tar.gz"):
        restore_script = f"""
if [ -f "{local_path}" ]; then
    cd / && tar xzf "{local_path}" 2>/dev/null
    echo "RESTORE_OK"
else
    echo "BACKUP_NOT_FOUND"
fi
"""
    else:
        restore_script = f"""
if [ -d "{local_path}" ]; then
    cp -rp {local_path}/etc/* /etc/ 2>/dev/null
    echo "RESTORE_OK"
else
    echo "BACKUP_NOT_FOUND"
fi
"""

    ok, output = _ansible_cmd(hostname, "shell", restore_script.replace('"', '\\"'), timeout=30)

    if ok and "RESTORE_OK" in output:
        db.twgcb_backups.update_one(
            {"hostname": hostname, "timestamp": backup_id},
            {"$set": {"restored_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")}}
        )
        return jsonify({"success": True, "message": f"還原完成（備份: {backup_id}）"})

    return jsonify({"success": False, "error": "還原失敗", "output": output[-300:]}), 500


@bp.route("/api/harden/status/<hostname>", methods=["GET"])
def harden_status(hostname):
    """取得主機強化狀態（有無備份、進度）"""
    db = get_db()

    # 最近的全備份
    last_full = db.twgcb_backups.find_one(
        {"hostname": hostname, "type": "full"},
        {"_id": 0},
        sort=[("timestamp", -1)]
    )

    # 掃描結果
    scan = db.twgcb_results.find_one({"hostname": hostname}, {"_id": 0})

    # 啟用的檢查項
    configs = list(db.twgcb_config.find({"enabled": True}, {"_id": 0}))

    has_backup = last_full is not None

    return jsonify({"success": True, "data": {
        "hostname": hostname,
        "has_backup": has_backup,
        "last_backup": last_full,
        "scan_result": scan,
        "enabled_checks": len(configs)
    }})


# 檢查項對應的影響檔案
CHECK_FILES_MAP = {
    "TWGCB-01-008-0108": ["/etc/sysctl.conf", "/etc/sysctl.d/99-twgcb.conf"],
    "TWGCB-01-008-0194": ["/etc/crontab"],
    "TWGCB-01-008-0205": ["/etc/cron.allow"],
    "TWGCB-01-008-0039": ["/etc/issue"],
    "TWGCB-01-008-0042": ["/etc/security/limits.conf", "/etc/security/limits.d/99-twgcb.conf"],
    "TWGCB-01-008-0274": ["/etc/ssh/sshd_config"],
    "TWGCB-01-008-0227": ["/etc/login.defs"],
    "TWGCB-01-008-0156": ["/etc/audit/rules.d/twgcb.rules"],
}


@bp.route("/api/harden/check-files/<check_id>", methods=["GET"])
def get_check_files(check_id):
    """取得檢查項影響的檔案清單"""
    files = CHECK_FILES_MAP.get(check_id, [])
    return jsonify({"success": True, "data": {"check_id": check_id, "files": files}})
