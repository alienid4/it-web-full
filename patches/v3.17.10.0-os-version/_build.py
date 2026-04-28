#!/usr/bin/env python3
"""v3.17.10.0 - hosts 加 os_version + 解析現有 os 字串"""
import os, re, ast
WORK = r"C:\Users\User\AppData\Local\Temp"
PATCH = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.17.10.0-os-version"

# ===== host_edit.html: OS 後面加 OS 版本 input =====
fp = os.path.join(WORK, "v31710_he.html")
with open(fp, encoding="utf-8") as f: s = f.read()

# 在 OS Group 之前插 OS 版本
old = '''<div class="form-group"><label>OS Group</label>'''
new = '''<div class="form-group"><label>OS 版本 (例: 9.6 / 13 / 2019)</label><input type="text" id="h-os-version" placeholder="9.6"></div>
      <div class="form-group"><label>OS Group</label>'''
if "h-os-version" not in s and old in s:
    s = s.replace(old, new, 1)
    print("[+] host_edit: OS 版本 input")

# JS: FIELD_IDS 加 os-version, ID_TO_DB 加 mapping
old_ids = '"hostname","ip","os","osgroup","env","status",'
new_ids = '"hostname","ip","os","os-version","osgroup","env","status",'
if "os-version" not in s.split("FIELD_IDS")[0] and old_ids in s:
    s = s.replace(old_ids, new_ids, 1)
    print("[+] FIELD_IDS 加 os-version")

old_map = '"os":"os","osgroup":"os_group",'
new_map = '"os":"os","os-version":"os_version","osgroup":"os_group",'
if old_map in s:
    s = s.replace(old_map, new_map, 1)
    print("[+] ID_TO_DB 加 os-version mapping")

with open(os.path.join(PATCH, "files", "webapp", "templates", "host_edit.html"), "w", encoding="utf-8") as f:
    f.write(s)

# ===== admin.js: 列表 OS 顯示 family + version =====
fp = os.path.join(WORK, "v31710_admin.js")
with open(fp, encoding="utf-8") as f: js = f.read()

old_os_display = "html += '<td>' + escapeHtml(h.os || \"-\") + osBadge + '</td>';"
new_os_display = '''var osDisplay = (h.os || "") + (h.os_version ? " " + h.os_version : "");
    html += '<td>' + escapeHtml(osDisplay || "-") + osBadge + '</td>';'''
if old_os_display in js:
    js = js.replace(old_os_display, new_os_display, 1)
    print("[+] admin.js list OS column 顯示 family + version")

with open(os.path.join(PATCH, "files", "webapp", "static", "js", "admin.js"), "w", encoding="utf-8") as f:
    f.write(js)

print("[done]")
