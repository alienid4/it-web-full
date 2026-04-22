#!/usr/bin/env bash
# user_admin.sh - 巡檢系統帳號管理工具 (menu 互動式)
# 用法: ./user_admin.sh

set -u

# ========== 顏色 ==========
R=$'\e[1;31m'
G=$'\e[1;32m'
Y=$'\e[1;33m'
B=$'\e[1;34m'
C=$'\e[1;36m'
W=$'\e[1;37m'
N=$'\e[0m'

# ========== 設定 ==========
DB_NAME="inspection"
MONGO_HOST="localhost"
MONGO_PORT="27017"
MONGO_URI="mongodb://${MONGO_HOST}:${MONGO_PORT}/${DB_NAME}"

# ========== 前置檢查 ==========
if ! command -v mongosh >/dev/null 2>&1; then
    printf "%s[錯誤] 找不到 mongosh%s\n" "$R" "$N"
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    printf "%s[錯誤] 找不到 python3%s\n" "$R" "$N"
    exit 1
fi
if ! python3 -c "import werkzeug, pymongo" 2>/dev/null; then
    printf "%s[錯誤] 缺 werkzeug 或 pymongo%s\n" "$R" "$N"
    printf "%s修法: pip3 install werkzeug pymongo%s\n" "$Y" "$N"
    exit 1
fi
if ! mongosh "$MONGO_URI" --quiet --eval "db.runCommand({ping:1})" >/dev/null 2>&1; then
    printf "%s[錯誤] 連不到 MongoDB (%s)%s\n" "$R" "$MONGO_URI" "$N"
    exit 1
fi

# ========== Mongo 查詢 helper ==========
mongo_eval() {
    mongosh "$MONGO_URI" --quiet --eval "$1"
}

pause() {
    printf "\n"
    read -r -p "按 Enter 回主選單..." _
}

# ========== 1. 列出全部帳號 ==========
list_users() {
    printf "%s=== 全部帳號 ===%s\n" "$C" "$N"
    mongo_eval '
    const rows = db.users.find({}, {_id:0, username:1, role:1, display_name:1, locked_until:1, login_failures:1, must_change_password:1, last_login:1}).toArray();
    if (rows.length === 0) { print("(無帳號)"); quit(); }
    print("USERNAME         ROLE         LOCKED  FAILS  MUST_CHG  LAST_LOGIN                    DISPLAY_NAME");
    print("---------------  -----------  ------  -----  --------  ----------------------------  --------------------");
    rows.forEach(r => {
        const u = (r.username || "").padEnd(15);
        const role = (r.role || "").padEnd(11);
        const locked = r.locked_until ? "YES" : "no ";
        const fails = String(r.login_failures || 0).padStart(5);
        const mustchg = r.must_change_password ? "YES     " : "no      ";
        const last = String(r.last_login || "(never)").padEnd(28).substring(0, 28);
        const dn = r.display_name || "";
        print(u + "  " + role + "  " + locked + "     " + fails + "  " + mustchg + "  " + last + "  " + dn);
    });
    print("");
    print("合計: " + rows.length + " 個帳號");
    '
}

# ========== 2. 帳號詳情 ==========
show_user_detail() {
    read -r -p "輸入 username: " uname
    [ -z "$uname" ] && { printf "%s已取消%s\n" "$Y" "$N"; return; }
    printf "%s=== %s 詳細資料 ===%s\n" "$C" "$uname" "$N"
    UNAME="$uname" mongosh "$MONGO_URI" --quiet --eval '
    const uname = process.env.UNAME;
    const u = db.users.findOne({username: uname}, {password_hash: 0});
    if (!u) { print("[找不到] " + uname); quit(); }
    printjson(u);
    print("");
    print("--- 登入鎖定紀錄 (login_attempts) ---");
    const a = db.login_attempts.findOne({username: uname});
    if (a) { printjson(a); } else { print("(無鎖定紀錄)"); }
    print("");
    print("--- 最近 5 筆稽核 log ---");
    db.audit_logs.find({username: uname}).sort({_id: -1}).limit(5).forEach(r => {
        print([r.created_at || r.timestamp || "?", r.action || "", r.detail || "", r.ip || ""].join(" | "));
    });
    '
}

# ========== 3. 解鎖 ==========
unlock_user() {
    read -r -p "輸入 username (或 'all' 解鎖全部): " uname
    [ -z "$uname" ] && { printf "%s已取消%s\n" "$Y" "$N"; return; }
    if [ "$uname" = "all" ]; then
        printf "%s確定解鎖全部帳號？[y/N]: %s" "$R" "$N"
        read -r ok
        [ "$ok" != "y" ] && { printf "%s已取消%s\n" "$Y" "$N"; return; }
        mongo_eval '
        const r1 = db.login_attempts.deleteMany({});
        const r2 = db.users.updateMany({}, {$set: {locked_until: null, login_failures: 0}});
        print("清除鎖定紀錄: " + r1.deletedCount + " 筆");
        print("重置帳號欄位: " + r2.modifiedCount + " 個");
        '
    else
        UNAME="$uname" mongosh "$MONGO_URI" --quiet --eval '
        const uname = process.env.UNAME;
        const r1 = db.login_attempts.deleteMany({username: uname});
        const r2 = db.users.updateOne({username: uname}, {$set: {locked_until: null, login_failures: 0}});
        if (r2.matchedCount === 0) { print("[找不到] " + uname); quit(); }
        print("[OK] 已解鎖 " + uname);
        print("  login_attempts 刪除: " + r1.deletedCount);
        print("  users 欄位重置: " + (r2.modifiedCount ? "OK" : "無變動"));
        '
    fi
}

# ========== 4. 重設密碼 ==========
reset_password() {
    read -r -p "輸入 username: " uname
    [ -z "$uname" ] && { printf "%s已取消%s\n" "$Y" "$N"; return; }

    exists=$(UNAME="$uname" mongosh "$MONGO_URI" --quiet --eval 'print(db.users.countDocuments({username: process.env.UNAME}))' | tr -d '[:space:]')
    if [ "$exists" != "1" ]; then
        printf "%s[錯誤] 找不到帳號 %s%s\n" "$R" "$uname" "$N"
        return
    fi

    read -r -s -p "新密碼 (不顯示): " pw1; echo
    [ -z "$pw1" ] && { printf "%s已取消 (密碼為空)%s\n" "$Y" "$N"; return; }
    read -r -s -p "再次輸入確認: " pw2; echo
    if [ "$pw1" != "$pw2" ]; then
        printf "%s[錯誤] 兩次密碼不一致%s\n" "$R" "$N"
        return
    fi

    UNAME="$uname" NEWPW="$pw1" python3 - <<'PYEOF'
import os, sys
from pymongo import MongoClient
from werkzeug.security import generate_password_hash
uname = os.environ["UNAME"]
newpw = os.environ["NEWPW"]
db = MongoClient("localhost", 27017)["inspection"]
r = db.users.update_one(
    {"username": uname},
    {"$set": {
        "password_hash": generate_password_hash(newpw),
        "locked_until": None,
        "login_failures": 0,
        "must_change_password": False,
    }}
)
db.login_attempts.delete_many({"username": uname})
if r.matched_count == 1:
    print("[OK] 密碼已更新，鎖定已清除")
else:
    print("[失敗] 未更新")
    sys.exit(1)
PYEOF
}

# ========== 5. 新增帳號 ==========
create_user_interactive() {
    read -r -p "新 username: " uname
    [ -z "$uname" ] && { printf "%s已取消%s\n" "$Y" "$N"; return; }

    exists=$(UNAME="$uname" mongosh "$MONGO_URI" --quiet --eval 'print(db.users.countDocuments({username: process.env.UNAME}))' | tr -d '[:space:]')
    if [ "$exists" != "0" ]; then
        printf "%s[錯誤] 帳號 %s 已存在%s\n" "$R" "$uname" "$N"
        return
    fi

    echo "角色: 1) oper  2) admin  3) superadmin"
    read -r -p "選擇 [1-3]: " rolech
    case "$rolech" in
        1) role="oper" ;;
        2) role="admin" ;;
        3) role="superadmin" ;;
        *) printf "%s已取消%s\n" "$Y" "$N"; return ;;
    esac

    read -r -p "顯示名稱: " dname
    read -r -s -p "密碼: " pw1; echo
    [ -z "$pw1" ] && { printf "%s已取消%s\n" "$Y" "$N"; return; }
    read -r -s -p "再次輸入: " pw2; echo
    if [ "$pw1" != "$pw2" ]; then
        printf "%s[錯誤] 兩次密碼不一致%s\n" "$R" "$N"
        return
    fi

    UNAME="$uname" NEWPW="$pw1" ROLE="$role" DNAME="$dname" python3 - <<'PYEOF'
import os, sys
sys.path.insert(0, "/opt/inspection/webapp")
try:
    from services.auth_service import create_user
    create_user(
        os.environ["UNAME"],
        os.environ["NEWPW"],
        role=os.environ["ROLE"],
        display_name=os.environ["DNAME"],
    )
    print("[OK] 帳號已建立，角色: " + os.environ["ROLE"])
except Exception as e:
    print("[失敗] " + str(e))
    sys.exit(1)
PYEOF
}

# ========== 6. 修改角色 ==========
change_role() {
    read -r -p "輸入 username: " uname
    [ -z "$uname" ] && { printf "%s已取消%s\n" "$Y" "$N"; return; }
    echo "新角色: 1) oper  2) admin  3) superadmin"
    read -r -p "選擇 [1-3]: " rolech
    case "$rolech" in
        1) role="oper" ;;
        2) role="admin" ;;
        3) role="superadmin" ;;
        *) printf "%s已取消%s\n" "$Y" "$N"; return ;;
    esac
    printf "%s確定把 %s 改為 %s？[y/N]: %s" "$R" "$uname" "$role" "$N"
    read -r ok
    [ "$ok" != "y" ] && { printf "%s已取消%s\n" "$Y" "$N"; return; }
    UNAME="$uname" ROLE="$role" mongosh "$MONGO_URI" --quiet --eval '
    const r = db.users.updateOne({username: process.env.UNAME}, {$set: {role: process.env.ROLE}});
    if (r.matchedCount === 0) { print("[找不到] " + process.env.UNAME); quit(); }
    print("[OK] 已更新角色: " + process.env.ROLE);
    '
}

# ========== 7. 刪除帳號 ==========
delete_user() {
    read -r -p "輸入要刪除的 username: " uname
    [ -z "$uname" ] && { printf "%s已取消%s\n" "$Y" "$N"; return; }
    printf "%s警告: 不可逆。再次輸入 username 確認: %s" "$R" "$N"
    read -r confirm
    if [ "$confirm" != "$uname" ]; then
        printf "%s已取消%s\n" "$Y" "$N"
        return
    fi
    UNAME="$uname" mongosh "$MONGO_URI" --quiet --eval '
    const r = db.users.deleteOne({username: process.env.UNAME});
    db.login_attempts.deleteMany({username: process.env.UNAME});
    if (r.deletedCount === 0) { print("[找不到] " + process.env.UNAME); quit(); }
    print("[OK] 已刪除 " + process.env.UNAME);
    '
}

# ========== 8. 最近登入紀錄 ==========
show_recent_logins() {
    read -r -p "顯示幾筆 [預設 20]: " n
    n="${n:-20}"
    printf "%s=== 最近 %s 筆登入紀錄 ===%s\n" "$C" "$n" "$N"
    LIMIT="$n" mongosh "$MONGO_URI" --quiet --eval '
    const lim = parseInt(process.env.LIMIT) || 20;
    db.audit_logs.find({action: {$in: ["login", "login_fail", "logout", "change_password"]}})
        .sort({_id: -1}).limit(lim).forEach(r => {
            print([r.created_at || r.timestamp || "?", (r.username || "").padEnd(12), (r.action || "").padEnd(16), r.ip || "", r.detail || ""].join(" | "));
        });
    '
}

# ========== 9. 診斷登入問題 ==========
diagnose_login() {
    read -r -p "輸入要診斷的 username: " uname
    [ -z "$uname" ] && { printf "%s已取消%s\n" "$Y" "$N"; return; }
    read -r -s -p "(選填) 輸入密碼驗證 (直接 Enter 跳過): " pw; echo
    echo
    printf "%s====== 登入診斷: %s ======%s\n" "$C" "$uname" "$N"

    # [1/7] MongoDB
    printf "%s[1/7]%s MongoDB 連線... " "$W" "$N"
    if mongosh "$MONGO_URI" --quiet --eval "db.runCommand({ping:1})" >/dev/null 2>&1; then
        printf "%sOK%s\n" "$G" "$N"
    else
        printf "%s失敗 <- 根因%s\n" "$R" "$N"
        printf "       %s修法: systemctl status mongod / podman ps%s\n" "$Y" "$N"
        return
    fi

    # [2/7] Flask service
    printf "%s[2/7]%s Flask 服務... " "$W" "$N"
    if systemctl is-active itagent-web >/dev/null 2>&1; then
        printf "%srunning%s\n" "$G" "$N"
    else
        printf "%s未運作 <- 根因%s\n" "$R" "$N"
        printf "       %s修法: systemctl start itagent-web%s\n" "$Y" "$N"
        return
    fi

    # [3/7] Port 5000
    printf "%s[3/7]%s Port 5000 監聽... " "$W" "$N"
    if ss -tln 2>/dev/null | grep -q ':5000 ' || netstat -an 2>/dev/null | grep -q ':5000.*LISTEN'; then
        printf "%sOK%s\n" "$G" "$N"
    else
        printf "%s未監聽%s\n" "$R" "$N"
    fi

    # [4/7] User exists
    printf "%s[4/7]%s 帳號是否存在... " "$W" "$N"
    exists=$(UNAME="$uname" mongosh "$MONGO_URI" --quiet --eval 'print(db.users.countDocuments({username: process.env.UNAME}))' | tr -d '[:space:]')
    if [ "$exists" = "1" ]; then
        printf "%s存在%s\n" "$G" "$N"
    else
        printf "%s找不到 <- 根因%s\n" "$R" "$N"
        printf "       %s修法: 選項 5 新建帳號，或確認拼字%s\n" "$Y" "$N"
        echo "       現有帳號:"
        mongo_eval 'db.users.find({}, {_id:0, username:1, role:1}).forEach(r => print("         - " + r.username + " (" + r.role + ")"))'
        return
    fi

    # [5/7] User fields
    printf "%s[5/7]%s 帳號欄位:\n" "$W" "$N"
    UNAME="$uname" mongosh "$MONGO_URI" --quiet --eval '
    const u = db.users.findOne({username: process.env.UNAME});
    print("         role              : " + (u.role || "(空)"));
    print("         password_hash     : " + (u.password_hash ? "[已設定, len=" + u.password_hash.length + "]" : "[空 <- 問題]"));
    print("         locked_until      : " + (u.locked_until || "null"));
    print("         login_failures    : " + (u.login_failures || 0));
    print("         must_change_pwd   : " + (u.must_change_password || false));
    print("         last_login        : " + (u.last_login || "(從未)"));
    '

    # [6/7] Lockout
    printf "%s[6/7]%s 鎖定狀態... " "$W" "$N"
    attempts=$(UNAME="$uname" mongosh "$MONGO_URI" --quiet --eval '
    const a = db.login_attempts.findOne({username: process.env.UNAME});
    print(a ? (a.attempts || 0) : 0);
    ' | tail -1 | tr -d '[:space:]')
    attempts="${attempts:-0}"
    if [ "$attempts" -ge 5 ] 2>/dev/null; then
        printf "%s已鎖定 (%s 次失敗) <- 根因%s\n" "$R" "$attempts" "$N"
        printf "       %s修法: 主選單 3) 解鎖帳號%s\n" "$Y" "$N"
        return
    elif [ "$attempts" -gt 0 ] 2>/dev/null; then
        printf "%s累積 %s 次失敗 (未達 5 次鎖定門檻)%s\n" "$Y" "$attempts" "$N"
    else
        printf "%s無%s\n" "$G" "$N"
    fi

    # [7/7] Live login test
    if [ -n "$pw" ]; then
        printf "%s[7/7]%s 密碼驗證 (透過 Flask API)... " "$W" "$N"
        tmp_resp=$(mktemp)
        code=$(curl -s -o "$tmp_resp" -w "%{http_code}" \
            -X POST http://127.0.0.1:5000/api/admin/login \
            -H "Content-Type: application/json" \
            --data-binary "@-" <<JSONEOF
{"username":"$uname","password":"$pw"}
JSONEOF
        )
        body=$(cat "$tmp_resp")
        rm -f "$tmp_resp"
        case "$code" in
            200) printf "%s成功 - 這組密碼可登入%s\n" "$G" "$N" ;;
            401) printf "%s密碼錯誤 <- 根因%s\n" "$R" "$N"
                 printf "       %s修法: 主選單 4) 重設密碼%s\n" "$Y" "$N"
                 echo "       回應: $body" ;;
            429) printf "%s被鎖定 <- 根因%s\n" "$R" "$N"
                 printf "       %s修法: 主選單 3) 解鎖帳號%s\n" "$Y" "$N"
                 echo "       回應: $body" ;;
            500) printf "%sFlask 500 <- 後端 bug%s\n" "$R" "$N"
                 printf "       %s看 journalctl -u itagent-web -n 50%s\n" "$Y" "$N"
                 echo "       回應: $body" ;;
            000) printf "%s連不到 Flask%s\n" "$R" "$N" ;;
            *) printf "%sHTTP %s%s: %s\n" "$Y" "$code" "$N" "$body" ;;
        esac
    else
        printf "%s[7/7]%s 密碼驗證... %s跳過%s\n" "$W" "$N" "$Y" "$N"
    fi
    printf "%s====== 診斷結束 ======%s\n" "$C" "$N"
}

# ========== 主選單 ==========
main_menu() {
    while true; do
        clear
        printf "%s========================================%s\n" "$B" "$N"
        printf "%s    巡檢系統 - 帳號管理工具%s\n" "$B" "$N"
        printf "%s    DB: %s@%s:%s%s\n" "$B" "$DB_NAME" "$MONGO_HOST" "$MONGO_PORT" "$N"
        printf "%s========================================%s\n" "$B" "$N"
        printf "  %s1)%s 列出全部帳號\n" "$W" "$N"
        printf "  %s2)%s 查看單一帳號詳情\n" "$W" "$N"
        printf "  %s3)%s 解鎖帳號 (清除鎖定)\n" "$W" "$N"
        printf "  %s4)%s 重設密碼\n" "$W" "$N"
        printf "  %s5)%s 新增帳號\n" "$W" "$N"
        printf "  %s6)%s 修改角色\n" "$W" "$N"
        printf "  %s7)%s 刪除帳號\n" "$R" "$N"
        printf "  %s8)%s 最近登入紀錄\n" "$W" "$N"
        printf "  %s9)%s 診斷登入問題 %s(一鍵排查 DB/鎖定/密碼)%s\n" "$G" "$N" "$C" "$N"
        printf "  %s0)%s 離開\n" "$Y" "$N"
        printf "%s----------------------------------------%s\n" "$B" "$N"
        read -r -p "選擇功能 [0-9]: " ch
        echo
        case "$ch" in
            1) list_users ;;
            2) show_user_detail ;;
            3) unlock_user ;;
            4) reset_password ;;
            5) create_user_interactive ;;
            6) change_role ;;
            7) delete_user ;;
            8) show_recent_logins ;;
            9) diagnose_login ;;
            0) printf "%s再見！%s\n" "$G" "$N"; exit 0 ;;
            *) printf "%s無效選項%s\n" "$R" "$N" ;;
        esac
        pause
    done
}

main_menu
