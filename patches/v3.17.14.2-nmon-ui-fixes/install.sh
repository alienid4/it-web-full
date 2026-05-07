#!/bin/bash
# v3.17.14.2 ??NMON UI ?耨
#
# Fix 1 (3.17.14.1): ?訾蜓璈??桀憿舐內 1 ??#   root cause: renderNmonHosts filter ??nmon_supported=false 雿?nmon_enabled=true ?蜓璈???#   (OS 甈?"-" ?蜓璈?憭梧?雿輻?瘜?????⊥??寥??
#
# Fix 2 (3.17.14.2): /perf ?梯”瘝???#   root cause: nmon cron ?其蜓璈璅???∟孛?潭???臬嚗mon_daily 蝛???/perf 蝛?#   solution: ??蝞∠? ???鞈??園???乓ard (?拇郊撽???
#
# ??: 撌脤蝵?v3.17.14.0 (NMON ?Ｙ? RPM 瘣暸?
# ?函蔡: sudo bash install.sh
set -e

PATCH_VER="3.17.14.2"
HERE="$(cd "$(dirname "$0")" && pwd)"
TS=$(date +%Y%m%d_%H%M%S)

# ---------- 1. ?菜葫 INSPECTION_HOME ----------
INSPECTION_HOME=""
for p in /opt/inspection /seclog/AI/inspection; do
    [ -f "$p/data/version.json" ] && INSPECTION_HOME="$p" && break
done
if [ -z "$INSPECTION_HOME" ]; then
    echo "[FAIL] ?曆???inspection ?桅?"
    exit 1
fi
echo "[INFO] INSPECTION_HOME=$INSPECTION_HOME"

# ---------- 2. 蝣箄? v3.17.14.0 撌脤蝵?----------
if ! grep -q "installNmonRpmFail" "$INSPECTION_HOME/webapp/static/js/admin.js" 2>/dev/null; then
    echo "[FAIL] ?菜葫銝 v3.17.14.0 ??installNmonRpmFail(), 隢??函蔡 v3.17.14.0"
    exit 1
fi
echo "[INFO] v3.17.14.0 撌脤蝵? 蝜潛?"

# ---------- 3. ?遢 ----------
backup() {
    [ -f "$1" ] && cp -av "$1" "${1}.bak.${TS}" && echo "[BACKUP] $1"
}
backup "$INSPECTION_HOME/webapp/templates/admin.html"
backup "$INSPECTION_HOME/webapp/static/js/admin.js"

# ---------- 4. Fix 1: admin.js filter/disabled (3.17.14.1) ----------
echo "[INFO] Fix 1: 靽?renderNmonHosts filter/disabled (OS?芸皜砍歇?銝餅??航?)"
if grep -q "nmon_supported && !h.nmon_enabled) return false" "$INSPECTION_HOME/webapp/static/js/admin.js"; then
    echo "[SKIP] Fix 1 撌脣???
else
    sed -i 's/if (!showAll \&\& !h\.nmon_supported) return false;/if (!showAll \&\& !h.nmon_supported \&\& !h.nmon_enabled) return false;/' \
        "$INSPECTION_HOME/webapp/static/js/admin.js"
    sed -i 's/var disabled = !h\.nmon_supported;/var disabled = !h.nmon_supported \&\& !h.nmon_enabled;/' \
        "$INSPECTION_HOME/webapp/static/js/admin.js"
    echo "[OK] Fix 1 摰?"
fi

# ---------- 5. Fix 2: admin.html ????臬 card (3.17.14.2) ----------
echo "[INFO] Fix 2: inject 鞈??園?+?臬 card ??admin.html"
if grep -q "nmon-collect-btn" "$INSPECTION_HOME/webapp/templates/admin.html"; then
    echo "[SKIP] Fix 2 admin.html 撌脣???
else
    python3 - "$INSPECTION_HOME/webapp/templates/admin.html" <<'PY_EOF'
import sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    html = f.read()

# ?曄?撠暸暺? nmon ?函蔡撽?蝯? card ??銝??</div> (tab-perf-mgmt ?撠?
# 憒??舐?????(瘝? verify card), ?寞??蝯?
anchors = [
    '  <!-- ===== nmon ?函蔡撽?蝯? ===== -->\n</div>',
    '  <!-- ===== nmon ??蝯? ===== -->\n</div>',
]
anchor = None
for a in anchors:
    if a in html:
        anchor = a
        break

if anchor is None:
    print('[FAIL] anchor not found, check admin.html structure')
    sys.exit(1)

card = '''  <!-- ===== nmon 鞈??園? + ?臬 (v3.17.14.2) ===== -->
  <div class="card" style="margin-top:16px;">
    <div class="card-title" style="display:flex;align-items:center;gap:12px;">
      ? 鞈??園????      <span style="font-size:11px;color:var(--c3);font-weight:400;">deploy 敺?憟敺???閫貊銝甈∴?敺???run_inspection.sh 瘥?芸??瑁?</span>
    </div>
    <div style="display:flex;gap:12px;flex-wrap:wrap;align-items:flex-start;">
      <div style="flex:1;min-width:220px;">
        <div style="font-size:13px;color:var(--c2);margin-bottom:6px;font-weight:600;">Step 1嚗??.nmon 瑼?/div>
        <div style="font-size:11px;color:var(--c3);margin-bottom:10px;">ansible 敺?銝餅? fetch ?餈?2 憭拍? .nmon ?唳?嗥?暺?data/nmon/</div>
        <button class="btn btn-primary" onclick="nmonCollectNow()" id="nmon-collect-btn">? 蝡?園?</button>
        <div id="nmon-collect-status" style="font-size:11px;color:var(--c3);margin-top:8px;white-space:pre-wrap;"></div>
      </div>
      <div style="flex:1;min-width:220px;">
        <div style="font-size:13px;color:var(--c2);margin-bottom:6px;font-weight:600;">Step 2嚗??MongoDB</div>
        <div style="font-size:11px;color:var(--c3);margin-bottom:10px;">閫?? data/nmon/ ??.nmon 瑼?撖怠 nmon_daily collection嚗?perf 撠望?鞈?</div>
        <button class="btn" style="background:var(--g2);color:white;" onclick="nmonImportNow()" id="nmon-import-btn">? ?臬 MongoDB</button>
        <div id="nmon-import-status" style="font-size:11px;color:var(--c3);margin-top:8px;white-space:pre-wrap;"></div>
      </div>
    </div>
  </div>
  <!-- ===== nmon 鞈??園?蝯? ===== -->
</div>'''

html = html.replace(anchor, anchor.replace('</div>', '') + card, 1)
with open(path, 'w', encoding='utf-8') as f:
    f.write(html)
print('[OK] admin.html inject done')
PY_EOF
fi

# ---------- 6. Fix 2: admin.js append JS functions ----------
echo "[INFO] Fix 2: append nmonCollectNow/nmonImportNow ??admin.js"
if grep -q "nmonCollectNow" "$INSPECTION_HOME/webapp/static/js/admin.js"; then
    echo "[SKIP] Fix 2 admin.js 撌脣???
else
    cat >> "$INSPECTION_HOME/webapp/static/js/admin.js" << 'JSEOF'

// ===== v3.17.14.2: nmon 鞈??園? + ?臬?? =====
function nmonCollectNow() {
  var btn = document.getElementById('nmon-collect-btn');
  var st = document.getElementById('nmon-collect-status');
  if (btn) { btn.disabled = true; btn.textContent = '???園?銝?(ansible fetch, 蝝?-3??...'; }
  if (st) st.textContent = '';
  fetch('/api/nmon/collect', {method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'})
    .then(function(r){return r.json();})
    .then(function(j){
      if (btn) { btn.disabled = false; btn.textContent = '? 蝡?園?'; }
      if (j.success) {
        if (st) st.textContent = '????瑁?銝哨?摰?敺????MongoDB?n銝餅?: ' + (j.limit||[]).join(', ');
      } else {
        if (st) st.textContent = '??' + (j.error || 'unknown');
      }
    }).catch(function(e){
      if (btn) { btn.disabled = false; btn.textContent = '? 蝡?園?'; }
      if (st) st.textContent = '??' + e;
    });
}

function nmonImportNow() {
  var btn = document.getElementById('nmon-import-btn');
  var st = document.getElementById('nmon-import-status');
  if (btn) { btn.disabled = true; btn.textContent = '???臬銝?..'; }
  if (st) st.textContent = '';
  fetch('/api/nmon/import', {method:'POST', headers:{'Content-Type':'application/json'}, body:'{}'})
    .then(function(r){return r.json();})
    .then(function(j){
      if (btn) { btn.disabled = false; btn.textContent = '? ?臬 MongoDB'; }
      if (j.success) {
        var d = j.data || {};
        if (st) st.textContent = '??scanned=' + (d.scanned||0) + ' imported=' + (d.imported||0) + ' skipped=' + (d.skipped||0)
          + (d.failed&&d.failed.length ? '\n??failed: '+d.failed.slice(0,3).join(', ') : '')
          + '\n???曉?臬???賣??晞??亦?鞈?';
      } else {
        if (st) st.textContent = '??' + (j.error || 'unknown');
      }
    }).catch(function(e){
      if (btn) { btn.disabled = false; btn.textContent = '? ?臬 MongoDB'; }
      if (st) st.textContent = '??' + e;
    });
}
// ===== END nmon 鞈??園? =====
JSEOF
    echo "[OK] Fix 2 admin.js done"
fi

# ---------- 7. ?湔 version.json ----------
VERSION_JSON="$INSPECTION_HOME/data/version.json"
if [ -f "$VERSION_JSON" ]; then
    cp "$VERSION_JSON" "${VERSION_JSON}.bak.${TS}"
    python3 - "$VERSION_JSON" "$PATCH_VER" <<'PY_EOF'
import json, sys, datetime
path, ver = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    j = json.load(f)
j['version'] = ver
j['updated_at'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
log_entry = ver + " - " + datetime.datetime.now().strftime('%Y-%m-%d') + ": NMON UI ?耨: (1) ?訾蜓璈???OS?芸皜砍歇?銝餅??航?+?舫 (2) ?啣?鞈??園?/?臬??霈?/perf ????
j.setdefault('changelog', []).insert(0, log_entry)
with open(path, 'w', encoding='utf-8') as f:
    json.dump(j, f, ensure_ascii=False, indent=2)
print("[OK] version.json ? " + ver)
PY_EOF
fi

# ---------- 8. ?? webapp ----------
echo "[INFO] ?? itagent-web"
if systemctl is-active itagent-web >/dev/null 2>&1; then
    systemctl restart itagent-web
    ok=0
    for i in 1 2 3 4 5; do
        sleep 2
        HTTP=$(curl -sI -m 3 -o /dev/null -w "%{http_code}" http://127.0.0.1:5000/login 2>/dev/null || echo 000)
        if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then ok=1; break; fi
        echo "[INFO] 蝑?... ($i/5, http=${HTTP})"
    done
    if [ $ok -eq 1 ]; then
        echo "[OK] itagent-web ???? (HTTP $HTTP)"
    else
        echo "[FAIL] itagent-web 瘝絲靘? ??journalctl -u itagent-web -n 50"
        exit 1
    fi
else
    echo "[SKIP] itagent-web ?芾?"
fi

echo
echo "========================================"
echo "  v3.17.14.2 ?函蔡摰?"
echo "========================================"
echo "撽?:"
echo "  1. 蝟餌絞蝞∠? ????蝞∠? ??銝餅?皜?＊蝷箸??蜓璈?(??OS ?芸皜祉?撌脣??其蜓璈?"
echo "  2. ??蝞∠? ???摨 ??????鞈??園???乓ard"
echo "  3. 暺??蝡?園??? 蝑?1-3 ??"
echo "  4. 暺???臬 MongoDB?? ??scanned/imported ?詨?"
echo "  5. ??/perf ?? ???訾蜓璈????豢?隞???????
echo
echo "?遢:"
ls -la "${INSPECTION_HOME}"/webapp/{templates/admin.html,static/js/admin.js}.bak.${TS} 2>/dev/null || true
