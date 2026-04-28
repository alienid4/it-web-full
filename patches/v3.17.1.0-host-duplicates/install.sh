#!/bin/bash
# v3.17.1.0 重複/相似主機偵測 (Phase 2 of CMDB 整合)
set -e
PATCH_VER="3.17.1.0"
HERE="$(cd "$(dirname "$0")" && pwd)"
INSPECTION_HOME=""
for p in /seclog/AI/inspection /opt/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
[ -z "$INSPECTION_HOME" ] && { echo "FAIL"; exit 1; }
TS=$(date +%Y%m%d_%H%M%S)

echo "[1/4] 備份"
for f in webapp/app.py webapp/routes/api_admin.py webapp/templates/admin.html; do
    cp "$INSPECTION_HOME/$f" "$INSPECTION_HOME/$f.bak.${TS}"
done
echo "      OK (3 檔)"

echo ""
echo "[2/4] 部署"
cp "$HERE/files/webapp/app.py"                       "$INSPECTION_HOME/webapp/app.py"
cp "$HERE/files/webapp/routes/api_admin.py"          "$INSPECTION_HOME/webapp/routes/api_admin.py"
cp "$HERE/files/webapp/templates/admin.html"         "$INSPECTION_HOME/webapp/templates/admin.html"
cp "$HERE/files/webapp/templates/host_duplicates.html" "$INSPECTION_HOME/webapp/templates/host_duplicates.html"
cp "$HERE/files/webapp/services/host_dedup.py"       "$INSPECTION_HOME/webapp/services/host_dedup.py"
chown -R sysinfra:itagent "$INSPECTION_HOME/webapp" 2>/dev/null || true

echo ""
echo "[3/4] bump + 重啟"
python3 - <<PYEOF
import json
fp = "$INSPECTION_HOME/data/version.json"
with open(fp,encoding="utf-8") as f: d = json.load(f)
d["version"] = "$PATCH_VER"
d["updated_at"] = "$(date +'%Y-%m-%d %H:%M')"
d["changelog"] = ["$PATCH_VER - $(date +%Y-%m-%d): 重複/相似主機偵測 (P2 CMDB) — (1) services/host_dedup.py: find_similar_hosts (Levenshtein difflib ratio>=0.7 + alias 互含 + 共用 IP, score 排序) + merge_hosts (合併 aliases/ips, 刪 duplicate) (2) /admin/host-duplicates 全頁 + admin tab 加 🔍重複偵測 按鈕 (3) API: GET /api/admin/hosts/duplicates + POST /api/admin/hosts/merge"] + d["changelog"]
with open(fp,"w",encoding="utf-8") as f: json.dump(d,f,ensure_ascii=False,indent=2)
PYEOF
systemctl restart itagent-web && sleep 2 && systemctl restart itagent-tunnel
echo "      web=$(systemctl is-active itagent-web) tunnel=$(systemctl is-active itagent-tunnel)"

echo ""
echo "[4/4] smoke + contract"
set +e  # 允許失敗繼續印
ALL_OK=true
for u in /login /admin/host-duplicates; do
    H=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:5000$u")
    echo "  $u = $H"
    case "$H" in 200|302) ;; *) ALL_OK=false ;; esac
done

# Contract: 用 get_collection (相容 221, 沒有 get_hosts_col helper)
sudo -u sysinfra python3 <<PYEOF
import sys; sys.path.insert(0, "$INSPECTION_HOME/webapp")
try:
    from services.host_dedup import find_similar_hosts, merge_hosts
    pairs = find_similar_hosts()
    print(f"  contract: find_similar_hosts() 跑得起來, {len(pairs)} 對")
    if pairs:
        p = pairs[0]
        assert "host1" in p and "host2" in p and "score" in p and "reasons" in p
        print(f"  contract: pair[0] keys 齊全 ✓")
except Exception as e:
    print(f"  contract FAIL: {e}")
    sys.exit(1)
PYEOF
[ "$?" = "0" ] || ALL_OK=false

# log err
ERR_LOG=$(ls -t $INSPECTION_HOME/logs/*_run.log 2>/dev/null | head -1)
if [ -n "$ERR_LOG" ]; then
    ERR=$(tail -50 "$ERR_LOG" 2>/dev/null | grep -ciE "error|traceback|exception" || echo 0)
    echo "  最近 log err: $ERR"
fi

$ALL_OK && echo "" && echo "✅ v${PATCH_VER} smoke 全綠" || echo "" && echo "⚠️ smoke 有紅"

echo ""
echo "回滾:"
echo "  for f in app.py routes/api_admin.py templates/admin.html; do cp \$INSPECTION_HOME/webapp/\$f.bak.${TS} \$INSPECTION_HOME/webapp/\$f; done"
echo "  rm $INSPECTION_HOME/webapp/templates/host_duplicates.html"
echo "  rm $INSPECTION_HOME/webapp/services/host_dedup.py"
echo "  systemctl restart itagent-web itagent-tunnel"
