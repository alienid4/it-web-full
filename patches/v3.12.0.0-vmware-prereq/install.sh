#!/bin/bash
###############################################
#  v3.12.0.0-vmware-prereq installer
#  VMware tab 前置套件: pyvmomi + python-ldap
#
#  Usage:
#    sudo ./install.sh           # 互動模式 (遇覆蓋會問)
#    sudo ./install.sh -y        # 非互動模式 (全部 yes)
###############################################
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}OK${NC}   $1"; }
fail() { echo -e "  ${RED}FAIL${NC} $1"; exit 1; }
info() { echo -e "  ${CYAN}-->${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/files"
BUNDLE_TGZ="vmware_ldap_offline_v3.12.0.0.tar.gz"
BUNDLE_DIR_NAME="vmware_ldap_offline_v3.12.0.0"
EXTRACT_ROOT="/tmp/inspection_vmware_prereq_$$"
TS=$(date +%Y%m%d_%H%M%S)

AUTO_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) AUTO_YES=1 ;;
        -h|--help) echo "Usage: $0 [-y|--yes]"; exit 0 ;;
    esac
done

echo ""
echo -e "${CYAN}+====================================================+${NC}"
echo -e "${CYAN}|  v3.12.0.0-vmware-prereq                            |${NC}"
echo -e "${CYAN}|  pyvmomi 9.0 + python-ldap 3.4.3                    |${NC}"
echo -e "${CYAN}+====================================================+${NC}"
info "Mode: $([ $AUTO_YES -eq 1 ] && echo '非互動 (-y)' || echo '互動')"

# ========== [0] 前置 ==========
echo -e "${BOLD}[0/5] 前置檢查${NC}"
[ "$(id -u)" -eq 0 ] || fail "需 root / sudo"

# OS 檢查
if [ -f /etc/redhat-release ]; then
    OS_REL=$(cat /etc/redhat-release)
    info "OS: $OS_REL"
    case "$OS_REL" in
        *release\ 9*) ok "RHEL/Rocky 9 ✅" ;;
        *) warn "非 RHEL/Rocky 9，RPM 可能不相容" ;;
    esac
else
    warn "非 RHEL-based 系統，python-ldap RPM 可能裝不起來"
fi

# Python3 檢查
command -v python3 >/dev/null || fail "找不到 python3"
PYVER=$(python3 --version 2>&1)
info "$PYVER"

# tarball 檢查
[ -f "$SRC_DIR/$BUNDLE_TGZ" ] || fail "缺檔: $SRC_DIR/$BUNDLE_TGZ"
BUNDLE_SIZE=$(stat -c%s "$SRC_DIR/$BUNDLE_TGZ")
ok "bundle 檔齊全 ($(numfmt --to=iec $BUNDLE_SIZE))"

# 已裝狀態 (idempotent 檢查)
ALREADY_LDAP=0
ALREADY_PYV=0
python3 -c "import ldap" 2>/dev/null && ALREADY_LDAP=1
python3 -c "import pyVmomi" 2>/dev/null && ALREADY_PYV=1

if [ $ALREADY_LDAP -eq 1 ] && [ $ALREADY_PYV -eq 1 ]; then
    warn "兩個套件都已安裝"
    if [ $AUTO_YES -eq 0 ]; then
        read -p "仍要重跑安裝流程? [y/N] " ans
        [[ "$ans" =~ ^[Yy]$ ]] || { echo "取消"; exit 0; }
    else
        info "-y 模式，繼續重跑"
    fi
fi

# ========== [1] 解壓 bundle ==========
echo -e "${BOLD}[1/5] 解壓 bundle${NC}"
mkdir -p "$EXTRACT_ROOT"
tar xzf "$SRC_DIR/$BUNDLE_TGZ" -C "$EXTRACT_ROOT" || fail "解壓失敗"
BUNDLE_PATH="$EXTRACT_ROOT/$BUNDLE_DIR_NAME"
[ -d "$BUNDLE_PATH" ] || fail "解壓後找不到 $BUNDLE_DIR_NAME"
ok "解壓到 $BUNDLE_PATH"

# ========== [2] 裝 python3-ldap (RPM) ==========
echo -e "${BOLD}[2/5] 裝 python3-ldap (RPM)${NC}"
if [ $ALREADY_LDAP -eq 1 ] && [ $AUTO_YES -eq 0 ]; then
    ok "python-ldap 已裝，跳過"
else
    dnf localinstall -y "$BUNDLE_PATH"/rpms/python3-pyasn1-*.noarch.rpm \
                        "$BUNDLE_PATH"/rpms/python3-pyasn1-modules-*.noarch.rpm \
                        "$BUNDLE_PATH"/rpms/python3-ldap-*.x86_64.rpm 2>&1 | tail -10
    python3 -c "import ldap; print('python-ldap version:', ldap.__version__)" 2>/dev/null \
        && ok "python-ldap 安裝成功" \
        || fail "python-ldap 安裝失敗"
fi

# ========== [3] 裝 pyvmomi (wheel, --user) ==========
echo -e "${BOLD}[3/5] 裝 pyvmomi (wheel)${NC}"
# 用巡檢系統服務帳號 (sysinfra) 裝到它的 home，不是 root home
if id sysinfra >/dev/null 2>&1; then
    INSTALL_USER="sysinfra"
else
    INSTALL_USER=$(logname 2>/dev/null || echo "$SUDO_USER")
    [ -z "$INSTALL_USER" ] && INSTALL_USER="root"
fi
info "以 $INSTALL_USER 身分裝 pyvmomi (到 ~/.local)"

if [ $ALREADY_PYV -eq 1 ] && [ $AUTO_YES -eq 0 ]; then
    ok "pyvmomi 已裝，跳過"
else
    PIP_CMD="python3 -m pip install --user --no-index --find-links=$BUNDLE_PATH/wheels pyvmomi"
    [ $AUTO_YES -eq 1 ] && PIP_CMD="$PIP_CMD --force-reinstall"
    sudo -u "$INSTALL_USER" bash -c "$PIP_CMD" 2>&1 | tail -5
    sudo -u "$INSTALL_USER" python3 -c "import pyVmomi; print('pyvmomi version:', getattr(pyVmomi,'__version__','unknown'))" 2>/dev/null \
        && ok "pyvmomi 安裝成功 (user=$INSTALL_USER)" \
        || fail "pyvmomi 安裝失敗"
fi

# ========== [4] 驗證 ==========
echo -e "${BOLD}[4/5] 整體驗證${NC}"
# root 側
python3 -c "import ldap; print('  root:  python-ldap', ldap.__version__)" 2>/dev/null || warn "root 側 import ldap 失敗"
# install user 側
sudo -u "$INSTALL_USER" python3 -c "import pyVmomi, ldap
print('  $INSTALL_USER:  pyvmomi', getattr(pyVmomi,'__version__','?'), '| python-ldap', ldap.__version__)
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim
print('  SmartConnect/Disconnect/vim import OK')" 2>&1 | grep -v "^$" || warn "$INSTALL_USER 側驗證有異常"

# ========== [5] 清理 ==========
echo -e "${BOLD}[5/5] 清理暫存${NC}"
rm -rf "$EXTRACT_ROOT"
ok "已刪 $EXTRACT_ROOT"

echo ""
echo -e "${GREEN}${BOLD}╔═════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║  v3.12.0.0-vmware-prereq 完成               ║${NC}"
echo -e "${GREEN}${BOLD}╚═════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BOLD}下一步：vCenter 連通性測試 (Stage 0)${NC}"
echo "  cat $SCRIPT_DIR/../../notes/2026-04-24/2026-04-24_1335_vcenter-connectivity-test.md"
echo "  改 IP/帳密後跑 Stage 0 的 heredoc"
echo ""
echo -e "${BOLD}Rollback${NC}:"
echo "  sudo dnf remove python3-ldap python3-pyasn1-modules python3-pyasn1"
echo "  sudo -u $INSTALL_USER python3 -m pip uninstall pyvmomi -y"
