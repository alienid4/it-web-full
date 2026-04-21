#!/bin/bash
# ============================================
# 金融業 IT 每日自動巡檢系統 - 資安掃描腳本
# 用法:
#   bash security_scan.sh quick    # 快速掃描（打包前）
#   bash security_scan.sh standard # 標準掃描（版本發布前）
#   bash security_scan.sh full     # 完整掃描（年度/大版本）
# ============================================

INSPECTION_HOME="${INSPECTION_HOME:-/opt/inspection}"
LEVEL="${1:-quick}"
PASS=0
FAIL=0
WARN=0
REPORT=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_pass() { PASS=$((PASS+1)); REPORT="${REPORT}\n[PASS] $1"; echo -e "${GREEN}[PASS]${NC} $1"; }
log_fail() { FAIL=$((FAIL+1)); REPORT="${REPORT}\n[FAIL] $1"; echo -e "${RED}[FAIL]${NC} $1"; }
log_warn() { WARN=$((WARN+1)); REPORT="${REPORT}\n[WARN] $1"; echo -e "${YELLOW}[WARN]${NC} $1"; }
log_info() { REPORT="${REPORT}\n[INFO] $1"; echo -e "[INFO] $1"; }

echo "============================================"
echo "  資安掃描 - ${LEVEL} 模式"
echo "  掃描時間: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# ===== QUICK SCAN (每次打包前) =====

echo "--- [1/3] 密碼明文檢查 ---"

# 檢查 inventory 有無明文密碼
if grep -q "ansible_password:" "${INSPECTION_HOME}/ansible/inventory/hosts.yml" 2>/dev/null; then
  if grep "ansible_password:" "${INSPECTION_HOME}/ansible/inventory/hosts.yml" | grep -q "vault"; then
    log_pass "Ansible 密碼已加密 (Vault)"
  else
    log_fail "C-01: Ansible Inventory 含明文密碼"
  fi
else
  log_pass "Ansible Inventory 無明文密碼"
fi

# 檢查 settings.json 有無明文密碼
if grep -qE "smtp_pass|password" "${INSPECTION_HOME}/data/settings.json" 2>/dev/null; then
  SMTP_PASS=$(python3 -c "import json; d=json.load(open('${INSPECTION_HOME}/data/settings.json')); print(d.get('notify_email',{}).get('smtp_pass',''))" 2>/dev/null)
  if [ -n "$SMTP_PASS" ] && [ "$SMTP_PASS" != "" ] && [ "$SMTP_PASS" != "ENCRYPTED" ] && ! echo "$SMTP_PASS" | grep -q "^ENV:"; then
    log_fail "C-02: settings.json 含明文 SMTP 密碼"
  else
    log_pass "settings.json SMTP 密碼已處理"
  fi
fi

# 檢查 config.py SECRET_KEY
if grep -q 'example-inspection-secret\|change-me\|YOUR_' "${INSPECTION_HOME}/webapp/config.py" 2>/dev/null; then
  log_fail "H-02: SECRET_KEY 為預設值或硬編碼"
else
  log_pass "SECRET_KEY 已設定"
fi

echo ""
echo "--- [2/3] 執行環境檢查 ---"

# Debug Mode
DEBUG_VAL=$(grep "FLASK_DEBUG" "${INSPECTION_HOME}/webapp/config.py" 2>/dev/null | grep -oE "True|False")
if [ "$DEBUG_VAL" = "True" ]; then
  log_fail "H-01: Flask Debug Mode 開啟"
else
  log_pass "Flask Debug Mode 已關閉"
fi

# 檔案權限
for f in "${INSPECTION_HOME}/data/settings.json" "${INSPECTION_HOME}/webapp/config.py" "${INSPECTION_HOME}/ansible/inventory/hosts.yml"; do
  if [ -f "$f" ]; then
    PERM=$(stat -c %a "$f" 2>/dev/null)
    if [ "$PERM" = "600" ] || [ "$PERM" = "640" ]; then
      log_pass "檔案權限 OK: $(basename $f) ($PERM)"
    else
      log_warn "M-04: 檔案權限過寬: $(basename $f) ($PERM, 建議 600)"
    fi
  fi
done

# MongoDB 限制本地
MONGO_BIND=$(ss -tlnp 2>/dev/null | grep 27017 | awk '{print $4}')
if echo "$MONGO_BIND" | grep -q "127.0.0.1"; then
  log_pass "MongoDB 僅本地連線"
elif echo "$MONGO_BIND" | grep -q "0.0.0.0"; then
  log_fail "MongoDB 對外開放 (0.0.0.0:27017)"
else
  log_info "MongoDB 未運行或無法檢測"
fi

echo ""
echo "--- [3/3] 敏感資料檢查 ---"

# 掃描 __pycache__
PYCACHE_COUNT=$(find "${INSPECTION_HOME}/webapp" -name "__pycache__" 2>/dev/null | wc -l)
if [ "$PYCACHE_COUNT" -gt 0 ]; then
  log_warn "__pycache__ 存在 (${PYCACHE_COUNT} 個目錄)"
else
  log_pass "無 __pycache__"
fi

# 掃描 .bak 檔案
BAK_COUNT=$(find "${INSPECTION_HOME}" -name "*.bak" 2>/dev/null | wc -l)
if [ "$BAK_COUNT" -gt 0 ]; then
  log_warn ".bak 備份檔案存在 (${BAK_COUNT} 個)"
else
  log_pass "無 .bak 備份檔案"
fi

# ===== STANDARD SCAN (版本發布前) =====
if [ "$LEVEL" = "standard" ] || [ "$LEVEL" = "full" ]; then
  echo ""
  echo "--- [4/6] HTTP 安全性 ---"

  # 檢查 Flask 是否運行
  if ss -tlnp 2>/dev/null | grep -q ":5000"; then
    # Security Headers
    HEADERS=$(curl -sI http://localhost:5000/ 2>/dev/null)

    echo "$HEADERS" | grep -qi "X-Frame-Options" && log_pass "X-Frame-Options 已設定" || log_fail "M-01a: 缺少 X-Frame-Options"
    echo "$HEADERS" | grep -qi "X-Content-Type-Options" && log_pass "X-Content-Type-Options 已設定" || log_fail "M-01b: 缺少 X-Content-Type-Options"
    echo "$HEADERS" | grep -qi "Content-Security-Policy" && log_pass "Content-Security-Policy 已設定" || log_warn "M-01c: 缺少 Content-Security-Policy"
    echo "$HEADERS" | grep -qi "Referrer-Policy" && log_pass "Referrer-Policy 已設定" || log_warn "M-01d: 缺少 Referrer-Policy"

    # Server Header 洩漏
    if echo "$HEADERS" | grep -qi "Server: Werkzeug\|Server: Python"; then
      log_fail "M-02: Server Header 洩漏版本資訊"
    else
      log_pass "Server Header 未洩漏"
    fi

    # API 未授權存取
    for endpoint in "/api/hosts" "/api/inspections/latest" "/api/settings"; do
      CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:5000${endpoint}" 2>/dev/null)
      if [ "$CODE" = "200" ]; then
        log_fail "H-03: ${endpoint} 未授權可存取 (${CODE})"
      else
        log_pass "${endpoint} 需認證 (${CODE})"
      fi
    done
  else
    log_info "Flask 未運行，跳過 HTTP 檢查"
  fi

  echo ""
  echo "--- [5/6] 認證安全 ---"

  if ss -tlnp 2>/dev/null | grep -q ":5000"; then
    # 暴力破解測試
    LOCKOUT=false
    for i in $(seq 1 6); do
      CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
        -d "{\"username\":\"admin\",\"password\":\"wrong${i}\"}" http://localhost:5000/api/admin/login 2>/dev/null)
      if [ "$CODE" = "429" ] || [ "$CODE" = "403" ]; then
        LOCKOUT=true
        break
      fi
    done
    if [ "$LOCKOUT" = true ]; then
      log_pass "登入失敗鎖定機制有效"
    else
      log_fail "H-05: 無登入失敗鎖定（6 次錯誤仍可嘗試）"
    fi

    # NoSQL Injection
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" \
      -d '{"username":{"$gt":""},"password":{"$gt":""}}' http://localhost:5000/api/admin/login 2>/dev/null)
    if [ "$CODE" = "500" ]; then
      log_fail "C-03: NoSQL Injection 導致 500 錯誤"
    elif [ "$CODE" = "401" ] || [ "$CODE" = "400" ]; then
      log_pass "NoSQL Injection 已防護 (${CODE})"
    else
      log_warn "NoSQL Injection 回應異常 (${CODE})"
    fi
  fi

  echo ""
  echo "--- [6/6] 套件漏洞 ---"

  if command -v pip-audit &>/dev/null; then
    CVE_COUNT=$(pip-audit 2>/dev/null | grep -c "GHSA\|PYSEC\|CVE")
    if [ "$CVE_COUNT" -gt 0 ]; then
      log_fail "H-04: 發現 ${CVE_COUNT} 個已知套件漏洞"
    else
      log_pass "無已知套件漏洞"
    fi
  else
    log_info "pip-audit 未安裝，跳過 CVE 檢查"
  fi
fi

# ===== FULL SCAN (年度/大版本) =====
if [ "$LEVEL" = "full" ]; then
  echo ""
  echo "--- [7/8] CSRF 檢查 ---"
  if grep -rq "csrf\|CSRFProtect\|WTF" "${INSPECTION_HOME}/webapp/" 2>/dev/null; then
    log_pass "CSRF 保護已實作"
  else
    log_fail "M-06: 無 CSRF 保護"
  fi

  echo ""
  echo "--- [8/8] 完整性檢查 ---"
  # Cockpit 對外
  if ss -tlnp 2>/dev/null | grep -q ":9090"; then
    log_warn "L-01: Cockpit (9090) 對外開放"
  fi

  # Gunicorn
  if pgrep -f gunicorn &>/dev/null; then
    log_pass "使用 Gunicorn 生產伺服器"
  else
    log_warn "L-03: 使用 Flask 開發伺服器（建議 Gunicorn）"
  fi

  # HTTPS
  if ss -tlnp 2>/dev/null | grep -q ":443"; then
    log_pass "HTTPS 已啟用"
  else
    log_warn "M-05: 未啟用 HTTPS"
  fi
fi

# ===== 結果摘要 =====
echo ""
echo "============================================"
echo "  掃描結果 (${LEVEL})"
echo "============================================"
echo -e "  ${GREEN}PASS: ${PASS}${NC}"
echo -e "  ${YELLOW}WARN: ${WARN}${NC}"
echo -e "  ${RED}FAIL: ${FAIL}${NC}"
echo "============================================"

if [ "$FAIL" -gt 0 ]; then
  echo -e "  ${RED}結果: 未通過 — 有 ${FAIL} 個問題需修復${NC}"
  echo ""
  echo "  失敗項目:"
  echo -e "$REPORT" | grep "\[FAIL\]" | while read line; do echo "    $line"; done
  echo ""
  exit 1
else
  echo -e "  ${GREEN}結果: 通過${NC}"
  if [ "$WARN" -gt 0 ]; then
    echo -e "  ${YELLOW}（有 ${WARN} 個警告建議改善）${NC}"
  fi
  echo ""
  exit 0
fi
