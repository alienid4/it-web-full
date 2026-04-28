#!/usr/bin/env python3
"""v3.17.8.0 - 主機列表加搜尋/排序/快速篩選 + 換 3 個欄位"""
import os, re, sys
WORK = r"C:\Users\User\AppData\Local\Temp"
PATCH = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.17.8.0-hosts-filter-search"

# ===== 1. admin.html: tab-hosts panel 加 filter bar =====
fp = os.path.join(WORK, "v3180_admin.html")
with open(fp, encoding="utf-8") as f:
    s = f.read()

# 找 admin-hosts-list 那行,在它前面插 filter bar
old = '<div class="card"><div id="admin-hosts-list">載入中...</div></div>'
new = '''<!-- v3.17.8.0+ filter bar -->
  <style>
    .hosts-chip { display:inline-block; padding:4px 12px; margin:2px; border-radius:16px; background:#e5e7eb; color:#374151; border:1px solid #d1d5db; font-size:12px; cursor:pointer; transition:all .15s; }
    .hosts-chip:hover { background:#d1d5db; }
    .hosts-chip.active { background:#10b981; color:#fff; border-color:#059669; }
    .hosts-th-sortable { cursor:pointer; user-select:none; }
    .hosts-th-sortable:hover { background:#f0fdf4; }
  </style>
  <div class="card" style="padding:12px;margin-bottom:12px;">
    <input id="hosts-search" placeholder="🔍 搜尋 主機名稱 / IP / 資產名稱 / 附加說明 / 系統別" style="width:100%;padding:8px 10px;border:1px solid #ccc;border-radius:6px;font-size:14px;" oninput="renderHosts()">
    <div style="margin-top:8px;display:flex;gap:8px;flex-wrap:wrap;align-items:center;">
      <span style="font-weight:600;color:#374151;min-width:60px;">環境:</span>
      <span id="hosts-filter-env"></span>
    </div>
    <div style="margin-top:6px;display:flex;gap:8px;flex-wrap:wrap;align-items:center;">
      <span style="font-weight:600;color:#374151;min-width:60px;">OS:</span>
      <span id="hosts-filter-os"></span>
    </div>
    <div style="margin-top:6px;display:flex;gap:8px;flex-wrap:wrap;align-items:center;">
      <span style="font-weight:600;color:#374151;min-width:60px;">使用情境:</span>
      <span id="hosts-filter-usage"></span>
    </div>
    <div id="hosts-result-count" style="margin-top:8px;color:#6b7280;font-size:13px;"></div>
  </div>
  <div class="card"><div id="admin-hosts-list">載入中...</div></div>'''

if old in s:
    s = s.replace(old, new, 1)
    print("[+] admin.html tab-hosts 加 filter bar")
else:
    print("[!] tab-hosts marker 找不到")

with open(os.path.join(PATCH, "files", "webapp", "templates", "admin.html"), "w", encoding="utf-8") as f:
    f.write(s)

# ===== 2. admin.js: 重寫 loadHostsTab + 加 4 個 helper =====
fp = os.path.join(WORK, "v3180_admin.js")
with open(fp, encoding="utf-8") as f:
    js = f.read()

# 找 loadHostsTab 函式 (從 function 到 }) 整段替換
m = re.search(r"function loadHostsTab\(\) \{[\s\S]*?\n\}\n", js)
if not m:
    print("FAIL: loadHostsTab 找不到")
    sys.exit(1)

new_block = '''var _allHosts = [];
var _hostFilters = { env: null, os: null, usage: null };
var _hostSort = { key: "hostname", dir: "asc" };

function loadHostsTab() {
  fetch("/api/hosts?per_page=2000").then(function(r){return r.json();}).then(function(res) {
    _allHosts = res.data || [];
    if (!_allHosts.length) {
      document.getElementById("admin-hosts-list").innerHTML = '<div class="no-data">無主機</div>';
      return;
    }
    buildFilterChips();
    renderHosts();
  });
}

function buildFilterChips() {
  function distinct(arr) { return [...new Set(arr.filter(Boolean))].sort(); }
  var envs = distinct(_allHosts.map(function(h){return h.environment;}));
  var oss  = distinct(_allHosts.map(function(h){return h.os_group || h.os;}));
  var uses = distinct(_allHosts.map(function(h){return h.asset_usage;}));
  function html(arr, type) {
    return arr.map(function(v){
      var active = _hostFilters[type] === v ? " active" : "";
      return '<span class="hosts-chip' + active + '" onclick="hostsToggleFilter(\\'' + type + '\\',\\'' + String(v).replace(/'/g,"&#39;") + '\\')">' + escapeHtml(v) + '</span>';
    }).join("");
  }
  document.getElementById("hosts-filter-env").innerHTML = html(envs, "env");
  document.getElementById("hosts-filter-os").innerHTML = html(oss, "os");
  document.getElementById("hosts-filter-usage").innerHTML = html(uses, "usage") || '<span style="color:#9ca3af;font-size:12px;">尚無 (請至主機編輯填「資產用途」)</span>';
}

function hostsToggleFilter(type, value) {
  _hostFilters[type] = (_hostFilters[type] === value) ? null : value;
  buildFilterChips();
  renderHosts();
}

function hostsSetSort(key) {
  if (_hostSort.key === key) _hostSort.dir = _hostSort.dir === "asc" ? "desc" : "asc";
  else { _hostSort.key = key; _hostSort.dir = "asc"; }
  renderHosts();
}

function escapeHtml(s) {
  return String(s == null ? "" : s).replace(/[&<>"]/g, function(c){return ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"})[c];});
}

function renderHosts() {
  var search = (document.getElementById("hosts-search").value || "").trim().toLowerCase();
  var filtered = _allHosts.filter(function(h) {
    if (_hostFilters.env && h.environment !== _hostFilters.env) return false;
    if (_hostFilters.os) {
      var osg = h.os_group || h.os;
      if (osg !== _hostFilters.os) return false;
    }
    if (_hostFilters.usage && h.asset_usage !== _hostFilters.usage) return false;
    if (search) {
      var hay = [h.hostname, h.ip, h.asset_name, h.note, h.system_name, h.apid].concat(h.aliases || []).concat(h.ips || []).join(" ").toLowerCase();
      if (hay.indexOf(search) < 0) return false;
    }
    return true;
  });
  filtered.sort(function(a, b) {
    var av = (a[_hostSort.key] || "").toString();
    var bv = (b[_hostSort.key] || "").toString();
    if (av < bv) return _hostSort.dir === "asc" ? -1 : 1;
    if (av > bv) return _hostSort.dir === "asc" ? 1 : -1;
    return 0;
  });
  var arrow = function(k){ return _hostSort.key === k ? (_hostSort.dir === "asc" ? " ▲" : " ▼") : ""; };
  document.getElementById("hosts-result-count").innerHTML =
    "顯示 <b>" + filtered.length + "</b> / " + _allHosts.length + " 台" +
    ((_hostFilters.env || _hostFilters.os || _hostFilters.usage || search) ? ' <a href="javascript:hostsClearFilters()" style="color:#10b981;font-size:12px;">[清除全部 filter]</a>' : "");
  var html = '<table style="width:100%;">' +
    '<thead><tr>' +
    '<th class="hosts-th-sortable" onclick="hostsSetSort(\\'hostname\\')">主機名稱' + arrow("hostname") + '</th>' +
    '<th class="hosts-th-sortable" onclick="hostsSetSort(\\'ip\\')">IP' + arrow("ip") + '</th>' +
    '<th class="hosts-th-sortable" onclick="hostsSetSort(\\'os\\')">OS' + arrow("os") + '</th>' +
    '<th class="hosts-th-sortable" onclick="hostsSetSort(\\'environment\\')">環境' + arrow("environment") + '</th>' +
    '<th class="hosts-th-sortable" onclick="hostsSetSort(\\'asset_name\\')">資產名稱' + arrow("asset_name") + '</th>' +
    '<th>附加說明</th>' +
    '<th>操作</th>' +
    '</tr></thead><tbody>';
  filtered.forEach(function(h) {
    var hn = h.hostname;
    html += '<tr>';
    html += '<td><strong>' + escapeHtml(hn) + '</strong></td>';
    html += '<td>' + escapeHtml(h.ip || "-") + '</td>';
    html += '<td>' + escapeHtml(h.os || "-") + '</td>';
    html += '<td>' + escapeHtml(h.environment || "-") + '</td>';
    html += '<td>' + escapeHtml(h.asset_name || "-") + '</td>';
    html += '<td style="max-width:300px;overflow:hidden;text-overflow:ellipsis;" title="' + escapeHtml(h.note || "") + '">' + escapeHtml((h.note || "-").substring(0, 60)) + ((h.note || "").length > 60 ? "..." : "") + '</td>';
    html += '<td style="white-space:nowrap;">';
    html += '<a class="btn btn-sm" style="background:var(--g2);color:white;text-decoration:none;" href="/admin/host-edit/' + encodeURIComponent(hn) + '" target="_blank">📝 編輯</a> ';
    html += '<button class="btn btn-sm" style="background:var(--g1);color:white;" onclick="pingHost(\\'' + hn + '\\')">Ping</button> ';
    html += '<button class="btn btn-sm btn-danger" onclick="adminAction(\\'/api/admin/hosts/' + hn + '\\',\\'DELETE\\',\\'確定要刪除 ' + hn + '？\\')">刪除</button>';
    html += '</td></tr>';
  });
  html += '</tbody></table>';
  document.getElementById("admin-hosts-list").innerHTML = html;
}

function hostsClearFilters() {
  _hostFilters = { env: null, os: null, usage: null };
  document.getElementById("hosts-search").value = "";
  buildFilterChips();
  renderHosts();
}

'''

js = js[:m.start()] + new_block + js[m.end():]
print("[+] admin.js 重寫 loadHostsTab + 加 5 個 helper")

import ast
# JS 不用 ast, 但確認長度合理
print("admin.js bytes:", len(js))
with open(os.path.join(PATCH, "files", "webapp", "static", "js", "admin.js"), "w", encoding="utf-8") as f:
    f.write(js)
print("[+] 寫入 patch")
