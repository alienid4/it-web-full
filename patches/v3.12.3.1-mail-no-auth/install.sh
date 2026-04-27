#!/bin/bash
###############################################
#  v3.12.3.1-mail-no-auth installer
#
#  hot-fix: generate_report.py send_email 對 no-auth relay 場景失效
#           原邏輯: if cfg.get("smtp_user"): srv.login(user, pass)
#           bug: smtp_user 有值 smtp_pass 空 → srv.login(user, "") → relay 不支援 AUTH 報錯
#                "smtp auth extension not supported by server"
#
#  修法 (對齊 services/email_service.py 的邏輯):
#    1. user AND pass 都非空才 login
#    2. smtp_pass 支援 ENV:VAR_NAME 前綴 (從環境變數解)
#
#  PREREQ: v3.12.3.0 已套
#  Idempotent: 偵測 # v3.12.3.1 marker → skip
###############################################
set -u
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

echo ""
echo -e "${CYAN}+============================================================+${NC}"
echo -e "${CYAN}|  v3.12.3.1 hot-fix: no-auth SMTP relay 寄信修復            |${NC}"
echo -e "${CYAN}+============================================================+${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"

if [ -n "${INSPECTION_HOME:-}" ]; then
    HOME_DIR="$INSPECTION_HOME"
elif [ -f "/opt/inspection/data/version.json" ]; then
    HOME_DIR="/opt/inspection"
elif [ -f "/seclog/AI/inspection/data/version.json" ]; then
    HOME_DIR="/seclog/AI/inspection"
else
    fail "找不到 inspection home"
fi
info "inspection home: $HOME_DIR"

GEN_PY="$HOME_DIR/scripts/generate_report.py"
VERSION_JSON="$HOME_DIR/data/version.json"

[ -f "$GEN_PY" ]       || fail "缺檔: $GEN_PY"
[ -f "$VERSION_JSON" ] || fail "缺檔: $VERSION_JSON"

CUR_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
info "目前版本: $CUR_VER"

BACKUP_DIR="/var/backups/inspection/pre_v3.12.3.1_${TS}"
mkdir -p "$BACKUP_DIR"

# ========== [1] 備份 ==========
echo -e "${BOLD}[1/3] 備份${NC}"
cp -p "$GEN_PY"       "$BACKUP_DIR/" && ok "generate_report.py → bak"
cp -p "$VERSION_JSON" "$BACKUP_DIR/" && ok "version.json → bak"
info "備份: $BACKUP_DIR"

OWNER=$(stat -c "%U:%G" "$GEN_PY")

# ========== [2] 改 generate_report.py SMTP login 邏輯 ==========
echo -e "${BOLD}[2/3] 修 generate_report.py SMTP login 邏輯${NC}"
GEN_PY_PATH="$GEN_PY" python3 <<'PYEOF' || fail "改寫失敗"
import re, os, sys
p = os.environ["GEN_PY_PATH"]
s = open(p, encoding="utf-8").read()

if "# v3.12.3.1 no-auth fix" in s:
    print("  v3.12.3.1 已套, skip")
    sys.exit(0)

# 找原 login 行
old_pat = re.compile(
    r'^([ \t]*)if cfg\.get\("smtp_user"\): srv\.login\(cfg\["smtp_user"\], cfg\.get\("smtp_pass",""\)\)',
    re.MULTILINE
)
m = old_pat.search(s)
if not m:
    raise SystemExit("找不到原 login 行 (generate_report.py 結構變了?)")

indent = m.group(1)
new_block = (
    indent + "# v3.12.3.1 no-auth fix: user AND pass 都非空才 login + 支援 ENV: 前綴\n"
    + indent + "_pwd = cfg.get(\"smtp_pass\", \"\")\n"
    + indent + "if _pwd.startswith(\"ENV:\"):\n"
    + indent + "    import os as _os\n"
    + indent + "    _pwd = _os.environ.get(_pwd[4:], \"\")\n"
    + indent + "if cfg.get(\"smtp_user\") and _pwd:\n"
    + indent + "    srv.login(cfg[\"smtp_user\"], _pwd)"
)
s = old_pat.sub(new_block, s, count=1)
open(p, 'w', encoding="utf-8").write(s)
print("  login 行已改為 user+pass 雙檢查 + ENV: 解析")
PYEOF
chown "$OWNER" "$GEN_PY"
python3 -c "import ast; ast.parse(open('$GEN_PY').read())" 2>&1 || fail "generate_report.py 語法錯! 從 $BACKUP_DIR 還原"
ok "generate_report.py 改寫 + 語法 OK"

# ========== [3] version.json ==========
echo -e "${BOLD}[3/3] 更新 version.json → 3.12.3.1${NC}"
VERSION_JSON_PATH="$VERSION_JSON" CHANGELOG_FILE="$SCRIPT_DIR/CHANGELOG_ENTRY.txt" python3 <<'PYEOF' || fail "version.json 更新失敗"
import json, datetime, os
p = os.environ["VERSION_JSON_PATH"]
d = json.load(open(p))
new_entry = open(os.environ["CHANGELOG_FILE"]).read().strip()
if any(e.startswith("3.12.3.1 ") for e in d.get("changelog", [])):
    print("  changelog 已含 3.12.3.1, skip prepend")
else:
    d.setdefault("changelog", []).insert(0, new_entry)
d["version"] = "3.12.3.1"
d["updated_at"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")
json.dump(d, open(p, 'w'), ensure_ascii=False, indent=2)
print("  version.json → 3.12.3.1")
PYEOF
chown "$OWNER" "$VERSION_JSON"

NEW_VER=$(python3 -c "import json; print(json.load(open('$VERSION_JSON'))['version'])" 2>/dev/null || echo "?")
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.3.1 完成! $CUR_VER → $NEW_VER${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}如何驗${NC}:"
echo "  sudo $HOME_DIR/run_inspection.sh"
echo "  # 看 log: tail -f $HOME_DIR/logs/<TS>_run.log"
echo "  # 找 'Email sent to:' 字樣 (應該不再噴 'auth extension not supported')"
echo ""
echo -e "${BOLD}你的 case (no-auth relay)${NC}: smtp_user/smtp_pass 都應為空, 可在 admin#settings 確認"
echo "  (UI 有「清除 (no auth)」按鈕清掉 smtp_pass; smtp_user 直接編輯成空白即可)"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo cp -p $BACKUP_DIR/generate_report.py $GEN_PY"
echo "  sudo cp -p $BACKUP_DIR/version.json $VERSION_JSON"
