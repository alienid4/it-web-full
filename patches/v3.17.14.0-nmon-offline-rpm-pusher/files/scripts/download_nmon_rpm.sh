#!/bin/bash
# v3.17.14.0 - 在外網機器跑, 抓最新 nmon RPM 進 offline_bundle/nmon/
# 用途: 公司隔離環境 (EPEL 不通) 的主機沒有 nmon 套件可裝, 預先在家裡 / 外網主機抓好包進 patch.
#
# 使用方法:
#   bash scripts/download_nmon_rpm.sh             # 預設抓 EL9
#   bash scripts/download_nmon_rpm.sh 8           # 抓 EL8 (公司若是 RHEL/Rocky 8)
#   bash scripts/download_nmon_rpm.sh 9 8         # 同時抓 EL9 + EL8
#
# 需求: dnf-utils 套件 (含 dnf download, RHEL/Rocky 9 預設沒裝, 跑 yum install dnf-utils)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# offline_bundle 預期在 patches/v3.17.14.0-.../files/offline_bundle/nmon/ 或 INSPECTION_HOME/offline_bundle/nmon/
# 兩種位置都試
TARGET=""
for cand in \
    "$SCRIPT_DIR/../offline_bundle/nmon" \
    "$SCRIPT_DIR/../../offline_bundle/nmon" \
    "/opt/inspection/offline_bundle/nmon" \
    "/seclog/AI/inspection/offline_bundle/nmon" \
; do
    if [ -d "$cand" ]; then
        TARGET="$cand"
        break
    fi
done

if [ -z "$TARGET" ]; then
    echo "[FAIL] 找不到 offline_bundle/nmon 目錄, 試過:"
    echo "  - $SCRIPT_DIR/../offline_bundle/nmon"
    echo "  - $SCRIPT_DIR/../../offline_bundle/nmon"
    echo "  - /opt/inspection/offline_bundle/nmon"
    echo "  - /seclog/AI/inspection/offline_bundle/nmon"
    exit 1
fi

echo "[INFO] Target: $TARGET"
mkdir -p "$TARGET"

# 預設抓 EL9, 可傳參數 8 / 9 多版本
versions=("$@")
[ ${#versions[@]} -eq 0 ] && versions=("9")

for ver in "${versions[@]}"; do
    echo
    echo "===== Downloading nmon for EL${ver} ====="
    case "$ver" in
        9)
            # secansible 是 EL9, dnf download 直接抓
            tmpdir=$(mktemp -d)
            ( cd "$tmpdir" && dnf download nmon --resolve 2>&1 | tail -5 )
            mv "$tmpdir"/nmon-*.el9.x86_64.rpm "$TARGET/" 2>/dev/null && echo "[OK] EL9 RPM 已放 $TARGET/"
            rm -rf "$tmpdir"
            ;;
        8)
            # EL8 用 EPEL 直接 URL 抓 (本地 dnf 是 EL9 不能切 release)
            cd "$TARGET"
            EPEL8_URL="https://dl.fedoraproject.org/pub/epel/8/Everything/x86_64/Packages/n/"
            # 抓 listing 找最新 nmon-*.el8.*
            latest=$(curl -fsSL "$EPEL8_URL" 2>/dev/null | grep -oE 'nmon-[0-9a-z.]+-[0-9.]+\.el8\.x86_64\.rpm' | sort -V | tail -1)
            if [ -z "$latest" ]; then
                echo "[FAIL] 從 $EPEL8_URL 找不到 nmon EL8 RPM, 可能 URL 變動, 請手動抓"
                continue
            fi
            curl -fsSL -O "${EPEL8_URL}${latest}" && echo "[OK] EL8 RPM: $latest"
            ;;
        *)
            echo "[SKIP] 不支援 EL${ver} (目前只做 EL8 / EL9)"
            ;;
    esac
done

echo
echo "===== 結果 ====="
ls -la "$TARGET/"
echo
echo "下一步:"
echo "  1. 檢查 RPM 大小 / 簽章 (rpm -qpi 看版本)"
echo "  2. 在 patch 內 commit RPM 上 git, 帶進公司 198.13"
echo "  3. 到 webapp UI 點「📦 派送 RPM」"
