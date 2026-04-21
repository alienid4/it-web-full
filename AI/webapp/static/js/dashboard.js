/* Dashboard 前端邏輯 v1.7.2 - 無圖表版 */
var _allHostsData = [];

// Phase 2 #7A: 共用 toast（成功/失敗/資訊通知）
function _dashToast(text, type) {
  var bg = type === "success" ? "var(--g1)" : (type === "error" ? "var(--red)" : "var(--c2)");
  var icon = type === "success" ? "\u2713" : (type === "error" ? "\u2717" : "\u2139");
  var t = document.createElement("div");
  t.style.cssText = "position:fixed;top:80px;left:50%;transform:translateX(-50%);background:" + bg + ";color:white;padding:12px 24px;border-radius:12px;z-index:9999;font-size:14px;box-shadow:0 4px 20px rgba(0,0,0,0.3);display:flex;align-items:center;gap:10px;";
  t.innerHTML = '<span style="font-size:18px;">' + icon + "</span><span>" + text + "</span>";
  document.body.appendChild(t);
  setTimeout(function(){ t.remove(); }, 3500);
}

document.addEventListener("DOMContentLoaded", function() {
  if (document.getElementById("kpi-ok")) {
    loadDashboard();
  }
});

function loadDashboard() {
  Promise.all([
    fetch("/api/hosts/summary").then(function(r){return r.json();}),
    fetch("/api/inspections/latest").then(function(r){return r.json();})
  ]).then(function(results) {
    var summaryRes = results[0];
    var allRes = results[1];

    // KPI with percentage
    if (summaryRes.success) {
      var d = summaryRes.data;
      var total = d.total || 0;
      document.getElementById("kpi-ok").innerHTML = '<span style="opacity:0.3;vertical-align:middle;margin-right:4px;">' + (typeof CTIcon!=="undefined"?CTIcon.shieldOk:"") + '</span>' + (d.ok || 0);
      document.getElementById("kpi-warn").innerHTML = '<span style="opacity:0.3;vertical-align:middle;margin-right:4px;">' + (typeof CTIcon!=="undefined"?CTIcon.shieldWarn:"") + '</span>' + (d.warn || 0);
      document.getElementById("kpi-error").innerHTML = '<span style="opacity:0.3;vertical-align:middle;margin-right:4px;">' + (typeof CTIcon!=="undefined"?CTIcon.shieldError:"") + '</span>' + (d.error || 0);
      document.getElementById("kpi-total").innerHTML = '<span style="opacity:0.3;vertical-align:middle;margin-right:4px;">' + (typeof CTIcon!=="undefined"?CTIcon.server:"") + '</span>' + total;

      var okPct = total > 0 ? Math.round((d.ok||0)/total*100) : 0;
      var warnPct = total > 0 ? Math.round((d.warn||0)/total*100) : 0;
      var errPct = total > 0 ? Math.round((d.error||0)/total*100) : 0;

      var okPctEl = document.getElementById("kpi-ok-pct");
      var warnPctEl = document.getElementById("kpi-warn-pct");
      var errPctEl = document.getElementById("kpi-error-pct");
      var totalPctEl = document.getElementById("kpi-total-pct");

      if (okPctEl) okPctEl.textContent = okPct + "%";
      if (warnPctEl) warnPctEl.textContent = warnPct + "%";
      if (errPctEl) errPctEl.textContent = errPct + "%";
      if (totalPctEl) totalPctEl.textContent = "100%";
    }

    // All hosts table + OS stats
    if (allRes.success) {
      _allHostsData = allRes.data;
      renderAllHostsTable(allRes.data);
      checkUid0Alerts(allRes.data);
      renderOsStats(allRes.data);
      // 連線狀態檢查
      dashPingAll();
    }
  }).catch(function(e) {
    console.error("Dashboard load error:", e);
  });
}

// Phase 2 #7A: async-feedback 標準化（spinner + AbortController + toast + finally）
async function dashPingAll() {
  var scanBtn = document.getElementById("rescan-all-btn");
  var _origHTML = null;
  if (scanBtn) {
    _origHTML = scanBtn.innerHTML;
    scanBtn.disabled = true;
    scanBtn.style.opacity = "0.7";
    scanBtn.innerHTML = '<span class="spinner-sm" style="width:10px;height:10px;border-width:2px;vertical-align:middle;"></span> 掃描中';
  }
  var controller = new AbortController();
  var timeoutId = setTimeout(function(){ controller.abort(); }, 30000);
  try {
    var r = await fetch("/api/admin/hosts/ping-all", { signal: controller.signal });
    var res = await r.json();
    if (res.success) {
      window._dashPingData = res.data;
      applyDashPing(res.data);
      var cacheHint = res.cached ? "（快取 " + (res.age_sec || 0) + "s）" : "";
      _dashToast("連線檢查完成" + cacheHint, "success");
    } else {
      _dashToast("連線檢查失敗：" + (res.error || "未知錯誤"), "error");
    }
  } catch(e) {
    var emsg = (e.name === "AbortError") ? "連線檢查逾時（超過 30 秒）" : (e.message || "未知錯誤");
    _dashToast("連線檢查失敗：" + emsg, "error");
  } finally {
    clearTimeout(timeoutId);
    if (scanBtn) { scanBtn.disabled = false; scanBtn.style.opacity = ""; scanBtn.innerHTML = _origHTML; }
  }
}

function applyDashPing(data) {
  for (var hn in data) {
    var el = document.getElementById("dash-ping-" + hn);
    if (!el) continue;
    var row = document.getElementById("dash-row-" + hn);
    if (data[hn].reachable) {
      el.innerHTML = '<span style="display:inline-block;width:8px;height:8px;background:var(--g1);border-radius:50%;box-shadow:0 0 4px var(--g1);cursor:pointer;" title="在線 — 點擊重掃" onclick="rescanHost(\'' + hn + '\')"></span>';
      if (row) row.style.opacity = "1";
    } else {
      el.innerHTML = '<span class="badge" style="background:var(--red);color:white;font-size:10px;padding:2px 6px;animation:uid0-flash 1s infinite;cursor:pointer;" onclick="rescanHost(\'' + hn + '\')" title="點擊重掃">離線</span>';
      if (row) row.style.opacity = "0.5";
    }
  }
}

function rescanHost(hostname) {
  var el = document.getElementById("dash-ping-" + hostname);
  if (el) el.innerHTML = '<span style="font-size:10px;color:var(--c3);">掃描中...</span>';
  fetch("/api/admin/hosts/" + hostname + "/ping", {method:"POST",credentials:"include"})
    .then(function(r){return r.json();}).then(function(res) {
      if (!window._dashPingData) window._dashPingData = {};
      window._dashPingData[hostname] = {reachable: res.reachable, ip: ""};
      var d = {}; d[hostname] = window._dashPingData[hostname];
      applyDashPing(d);
    }).catch(function(){
      if (el) el.innerHTML = '<span style="font-size:10px;color:var(--red);">失敗</span>';
    });
}

function toggleAbnormalFilter() {
  var cb = document.getElementById("abnormal-toggle");
  var track = document.getElementById("toggle-track");
  var thumb = document.getElementById("toggle-thumb");
  cb.checked = !cb.checked;
  if (cb.checked) {
    track.style.background = "var(--g1)";
    thumb.style.left = "20px";
  } else {
    track.style.background = "var(--c4)";
    thumb.style.left = "2px";
  }
  renderAllHostsTable(_allHostsData);
}

function renderAllHostsTable(data) {
  var tbody = document.getElementById("all-hosts-table");
  if (!tbody) return;
  var toggle = document.getElementById("abnormal-toggle");
  var showAbnormalOnly = toggle ? toggle.checked : true;
  var filtered = data;
  if (showAbnormalOnly) {
    filtered = data.filter(function(h) { return (h.overall_status || "ok").trim() !== "ok"; });
  }
  if (!filtered.length) {
    tbody.innerHTML = '<tr><td colspan="8" class="no-data">' + (showAbnormalOnly ? "所有主機狀態正常，無異常項目" : "無主機資料") + '</td></tr>';
    return;
  }
  tbody.innerHTML = filtered.map(function(h) {
    var s = (h.overall_status || "ok").trim();
    var disk = h.disk || (h.results && h.results.disk) || {};
    var cpu = h.cpu || (h.results && h.results.cpu) || {};
    var svc = h.service || (h.results && h.results.service) || {};
    var acct = h.account || (h.results && h.results.account) || {};
    var maxDisk = (disk.partitions || []).reduce(function(m, p){return Math.max(m, parseInt(p.percent) || 0);}, 0);
    var statusText = s === "ok" ? "正常" : s === "warn" ? "警告" : "異常";
    return '<tr id="dash-row-' + h.hostname + '"><td><a href="/report/' + h.hostname + '" style="color:var(--g2);text-decoration:none;font-weight:700;">' + h.hostname + '</a> <span id="dash-ping-' + h.hostname + '"></span></td><td>' + (h.ip || "") + '</td><td>' + (h.os || "") + '</td><td><span class="badge badge-' + s + '">' + statusText + '</span></td><td>' + maxDisk + '%</td><td>' + (cpu.cpu_percent || cpu.percent || "-") + '%</td><td><span class="badge badge-' + ((svc.status || "ok").trim()) + '">' + ((svc.status || "ok").trim()) + '</span></td><td><span class="badge badge-' + ((acct.status || "ok").trim()) + '">' + ((acct.status || "ok").trim()) + '</span></td></tr>';
  }).join("");
}

function checkUid0Alerts(data) {
  var alertArea = document.getElementById("uid0-alert-area");
  if (!alertArea) return;
  var hasUid0 = data.some(function(h) {
    var acct = h.account || (h.results && h.results.account) || {};
    return acct.uid0_alert || (acct.accounts_added || []).some(function(a){return (a.uid || "") === "0";});
  });
  if (hasUid0) alertArea.style.display = "block";
}

function renderOsStats(data) {
  var el = document.getElementById("os-stats");
  if (!el) return;
  var total = data.length || 1;
  var counts = {};
  var colors = {"Rocky":"#4AB234","RHEL":"#E00B00","Debian":"#E87C07","Windows":"#0078D4","AIX":"#555","SNMP":"#888","AS400":"#333"};
  data.forEach(function(h) {
    var os = (h.os || "unknown").split(" ")[0];
    if (os.indexOf("Windows") >= 0 || os.indexOf("Win") >= 0) os = "Windows";
    counts[os] = (counts[os] || 0) + 1;
  });
  var html = "";
  Object.keys(counts).sort(function(a,b){return counts[b]-counts[a];}).forEach(function(os) {
    var n = counts[os];
    var pct = Math.round(n / total * 100);
    var color = colors[os] || "var(--c3)";
    html += '<div style="flex:1;min-width:120px;">';
    html += '<div style="display:flex;justify-content:space-between;margin-bottom:4px;">';
    var osIcon = (typeof CTIcon!=="undefined") ? (os.indexOf("Windows")>=0||os.indexOf("Win")>=0?CTIcon.windows : os==="SNMP"||os==="Network"?CTIcon.network : CTIcon.linux) : "";
    html += '<span style="font-size:13px;font-weight:500;display:flex;align-items:center;gap:6px;">' + osIcon + os + '</span>';
    html += '<span style="font-family:JetBrains Mono;font-size:13px;">' + n + ' <span style="color:var(--c3);">(' + pct + '%)</span></span>';
    html += '</div>';
    html += '<div class="progress-bar" style="height:8px;"><div class="progress-fill" style="width:' + pct + '%;background:' + color + ';border-radius:4px;"></div></div>';
    html += '</div>';
  });
  el.innerHTML = html;
}
