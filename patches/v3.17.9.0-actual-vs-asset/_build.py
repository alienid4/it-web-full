#!/usr/bin/env python3
"""v3.17.9.0 - 真實偵測 vs 資產表 對照 + 一鍵採用"""
import os, re, sys, ast
WORK = r"C:\Users\User\AppData\Local\Temp"
PATCH = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.17.9.0-actual-vs-asset"

# ===== 1. api_hosts.py: 加 import + annotate =====
fp = os.path.join(WORK, "v3190_api_hosts.py")
with open(fp, encoding="utf-8") as f:
    s = f.read()

old_imp = "from services.mongo_service import get_all_hosts, get_host, upsert_host, get_hosts_summary"
new_imp = "from services.mongo_service import get_all_hosts, get_host, upsert_host, get_hosts_summary\nfrom services.actuals_service import annotate_hosts, annotate_host, adopt_actual"
if "actuals_service" not in s:
    s = s.replace(old_imp, new_imp)
    print("[+] api_hosts: 加 actuals_service import")

# list_hosts annotate
old_list = '''def list_hosts():
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 50, type=int)
    os_group = request.args.get("os_group")
    status = request.args.get("status")
    q = {}
    if os_group:
        q["os_group"] = os_group
    if status:
        q["status"] = status
    result = get_all_hosts(q, page, per_page)
    return jsonify({"success": True, **result})'''
new_list = '''def list_hosts():
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 50, type=int)
    os_group = request.args.get("os_group")
    status = request.args.get("status")
    q = {}
    if os_group:
        q["os_group"] = os_group
    if status:
        q["status"] = status
    result = get_all_hosts(q, page, per_page)
    # v3.17.9.0+: 對照 inspections 偵測值, 加 _actuals/_mismatches
    if isinstance(result.get("data"), list):
        annotate_hosts(result["data"])
    return jsonify({"success": True, **result})'''
if old_list in s:
    s = s.replace(old_list, new_list, 1)
    print("[+] api_hosts: list_hosts annotate")

# host_detail annotate
old_detail = '''def host_detail(hostname):
    h = get_host(hostname)
    if not h:
        return jsonify({"success": False, "error": "主機不存在", "code": 404}), 404
    return jsonify({"success": True, "data": h})'''
new_detail = '''def host_detail(hostname):
    h = get_host(hostname)
    if not h:
        return jsonify({"success": False, "error": "主機不存在", "code": 404}), 404
    # v3.17.9.0+
    annotate_host(h)
    return jsonify({"success": True, "data": h})'''
if old_detail in s:
    s = s.replace(old_detail, new_detail, 1)
    print("[+] api_hosts: host_detail annotate")

# 加 adopt_actual endpoint (POST /api/hosts/<hn>/adopt-actual)
if "adopt-actual" not in s:
    s += '''

@bp.route("/<hostname>/adopt-actual", methods=["POST"])
@login_required
def host_adopt_actual(hostname):
    """v3.17.9.0+: 把實際偵測值採用到 hosts (POST body: {"field": "os"})"""
    from decorators import admin_required
    data = request.get_json(force=True) or {}
    field = data.get("field", "")
    ok, msg = adopt_actual(hostname, field)
    return (jsonify({"success": True, "message": msg}) if ok else
            (jsonify({"success": False, "error": msg}), 400))
'''
    print("[+] api_hosts: 加 adopt-actual endpoint")

ast.parse(s)
with open(os.path.join(PATCH, "files", "webapp", "routes", "api_hosts.py"), "w", encoding="utf-8") as f:
    f.write(s)
print("[+] api_hosts.py AST OK")

# ===== 2. admin.js: hosts 表格加 WARN badge =====
fp = os.path.join(WORK, "v3190_admin.js")
with open(fp, encoding="utf-8") as f:
    js = f.read()

# 在 OS 欄位加 badge
old_os_td = "html += '<td>' + escapeHtml(h.os || \"-\") + '</td>';"
new_os_td = '''var osBadge = "";
    if (h._mismatches && h._mismatches.find(function(m){return m.field === "os";})) {
      var mm = h._mismatches.find(function(m){return m.field === "os";});
      osBadge = ' <span style="color:#dc2626;font-weight:700;cursor:help;" title="實際偵測: ' + escapeHtml(mm.actual) + '">WARN</span>';
    }
    html += '<td>' + escapeHtml(h.os || "-") + osBadge + '</td>';'''
if old_os_td in js:
    js = js.replace(old_os_td, new_os_td, 1)
    print("[+] admin.js: 主機列表 OS 欄位加 WARN badge")

# IP 欄位也加 badge
old_ip_td = "html += '<td>' + escapeHtml(h.ip || \"-\") + '</td>';"
new_ip_td = '''var ipBadge = "";
    if (h._mismatches && h._mismatches.find(function(m){return m.field === "ip";})) {
      var ipmm = h._mismatches.find(function(m){return m.field === "ip";});
      ipBadge = ' <span style="color:#dc2626;font-weight:700;cursor:help;" title="實際偵測: ' + escapeHtml(ipmm.actual) + '">WARN</span>';
    }
    html += '<td>' + escapeHtml(h.ip || "-") + ipBadge + '</td>';'''
if old_ip_td in js:
    js = js.replace(old_ip_td, new_ip_td, 1)
    print("[+] admin.js: 主機列表 IP 欄位加 WARN badge")

with open(os.path.join(PATCH, "files", "webapp", "static", "js", "admin.js"), "w", encoding="utf-8") as f:
    f.write(js)

# ===== 3. host_edit.html: 衝突警示 + 一鍵採用 =====
fp = os.path.join(WORK, "v3190_he.html")
with open(fp, encoding="utf-8") as f:
    html = f.read()

# 在 heLoad 內 fetch 完, 顯示 mismatch 警示
old_loaded_marker = '''    FIELD_IDS.forEach(id => {
      const el = document.getElementById("h-" + id);
      if (!el) return;
      const dbKey = ID_TO_DB[id];
      const v = h[dbKey];
      el.value = (v == null) ? (id === "quantity" ? 1 : "") : v;
    });'''
new_loaded = '''    FIELD_IDS.forEach(id => {
      const el = document.getElementById("h-" + id);
      if (!el) return;
      const dbKey = ID_TO_DB[id];
      const v = h[dbKey];
      el.value = (v == null) ? (id === "quantity" ? 1 : "") : v;
    });
    // v3.17.9.0+: 對照實際偵測值, 顯示 WARN 警示 + 一鍵採用
    showMismatchWarnings(h._mismatches || []);'''
if old_loaded_marker in html:
    html = html.replace(old_loaded_marker, new_loaded, 1)
    print("[+] host_edit: heLoad 後呼叫 showMismatchWarnings")

# 在 </script> 前加 showMismatchWarnings 函式
old_close = "document.addEventListener(\"DOMContentLoaded\", heLoad);"
new_close = '''function showMismatchWarnings(mismatches) {
  // 移除舊 banner
  document.querySelectorAll(".he-mismatch-banner").forEach(e => e.remove());
  if (!mismatches || !mismatches.length) return;
  // 在 sticky header 下方加 banner
  const banner = document.createElement("div");
  banner.className = "he-mismatch-banner";
  banner.style = "background:#fef3c7;border-left:4px solid #f59e0b;padding:14px 20px;margin:0 0 16px;font-size:14px;";
  let html = '<div style="font-weight:700;color:#92400e;margin-bottom:8px;">WARN 資產表填寫值跟實際偵測值不一致</div>';
  html += '<table style="font-size:13px;width:100%;"><thead><tr><th style="text-align:left;padding:4px;">欄位</th><th style="text-align:left;padding:4px;">資產表 (你填)</th><th style="text-align:left;padding:4px;">實際偵測</th><th></th></tr></thead><tbody>';
  const NAME = {os: "作業系統", ip: "IP", hostname: "主機名稱"};
  mismatches.forEach(m => {
    html += '<tr>' +
      '<td style="padding:4px;font-weight:600;">' + (NAME[m.field] || m.field) + '</td>' +
      '<td style="padding:4px;color:#dc2626;">' + escapeAttr(m.user) + '</td>' +
      '<td style="padding:4px;color:#059669;font-weight:600;">' + escapeAttr(m.actual) + '</td>' +
      '<td style="padding:4px;"><button class="btn btn-sm" style="background:#10b981;color:#fff;font-size:12px;" onclick="adoptActual(\\'' + m.field + '\\')">⇨ 一鍵採用實際值</button></td>' +
      '</tr>';
  });
  html += '</tbody></table>';
  banner.innerHTML = html;
  const wrap = document.querySelector(".he-wrap");
  if (wrap) wrap.insertBefore(banner, wrap.firstChild);
}

async function adoptActual(field) {
  if (!confirm("確定把「" + field + "」改成實際偵測值?\\n(改的是資產表記錄, 不影響真實主機)")) return;
  setMsg("採用中...");
  try {
    const r = await fetch("/api/hosts/" + encodeURIComponent(HE_HOSTNAME) + "/adopt-actual", {
      method: "POST", headers: {"Content-Type":"application/json"}, credentials: "include",
      body: JSON.stringify({field: field})
    });
    const res = await r.json();
    if (!res.success) { setMsg("失敗: " + (res.error || ""), "err"); return; }
    setMsg("✓ " + (res.message || "已採用"), "ok");
    setTimeout(heLoad, 500);  // 重抓資料
  } catch(e) { setMsg("錯誤: " + e.message, "err"); }
}

function escapeAttr(s) {
  return String(s == null ? "" : s).replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));
}

document.addEventListener("DOMContentLoaded", heLoad);'''

if old_close in html:
    html = html.replace(old_close, new_close, 1)
    print("[+] host_edit: 加 showMismatchWarnings + adoptActual")

with open(os.path.join(PATCH, "files", "webapp", "templates", "host_edit.html"), "w", encoding="utf-8") as f:
    f.write(html)

# ===== 4. mongo_service.py 不用改 (annotate 在 api 層) =====
print("\n[done]")
