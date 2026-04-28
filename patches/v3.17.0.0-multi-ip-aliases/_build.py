#!/usr/bin/env python3
"""Build v3.17.0.0 - hosts 加 ips array + aliases array"""
import os, re, sys

WORK = r"C:\Users\User\AppData\Local\Temp"
PATCH_DIR = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.17.0.0-multi-ip-aliases"

# ===== 1. host_edit.html: 加 ips + aliases UI =====
fp = os.path.join(WORK, "v3170_host_edit.html")
with open(fp, encoding="utf-8") as f:
    s = f.read()

# 在 IP 那一行後面加「副 IP」textarea + 在 hostname 之後加 aliases
old_ip_row = '<div class="form-group"><label>IP</label><input type="text" id="h-ip"></div>'
new_ip_block = '''<div class="form-group"><label>主 IP</label><input type="text" id="h-ip" placeholder="例: 192.168.1.221"></div>
      <div class="form-group"><label>其他 IP (一行一個, 選填)</label><textarea id="h-ips-extra" rows="2" placeholder="10.0.0.5&#10;10.0.0.6" style="width:100%;font-family:inherit;"></textarea></div>
      <div class="form-group"><label>主機別名 / 歷史名稱 (一行一個, 給搜尋用)</label><textarea id="h-aliases" rows="2" placeholder="server01&#10;srv-prd-01" style="width:100%;font-family:inherit;"></textarea></div>'''

if old_ip_row not in s:
    print("FAIL: 找不到 IP 那一行"); sys.exit(1)
s = s.replace(old_ip_row, new_ip_block, 1)
print("[+] IP block 改 multi + aliases")

# 改 FIELD_IDS / ID_TO_DB 加 ips-extra, aliases
# 因 ips/aliases 不是純 string, JS heLoad/heSave 要客製; 我們用 FIELD_IDS 處理 30 欄, 額外 2 欄手動處理

# 在 heLoad function 內 FIELD_IDS.forEach 之後加 ips/aliases 處理
old_load_end = '''      el.value = (v == null) ? (id === "quantity" ? 1 : "") : v;
    });'''
new_load_end = '''      el.value = (v == null) ? (id === "quantity" ? 1 : "") : v;
    });
    // ips array: 主 IP 已經由 "ip" 處理 (FIELD_IDS 內), 副 IP 從 ips[1:] 倒進 textarea
    const ipsArr = Array.isArray(h.ips) ? h.ips : [];
    const extras = ipsArr.length > 1 ? ipsArr.slice(1) : [];
    const extraEl = document.getElementById("h-ips-extra");
    if (extraEl) extraEl.value = extras.join("\\n");
    // aliases array
    const aliasesArr = Array.isArray(h.aliases) ? h.aliases : [];
    const aliasesEl = document.getElementById("h-aliases");
    if (aliasesEl) aliasesEl.value = aliasesArr.join("\\n");'''

if old_load_end not in s:
    print("FAIL: heLoad end marker not found"); sys.exit(1)
s = s.replace(old_load_end, new_load_end, 1)
print("[+] heLoad 加 ips/aliases load")

# 在 heSave 內加 ips/aliases 組合 (在 setMsg 前)
old_save_marker = '''  if (!data.hostname) { setMsg("主機名稱必填", "err"); return; }'''
new_save_marker = '''  // 組 ips array (主 IP 在 data.ip, 副 IP 從 textarea 拆)
  const extraIPs = (document.getElementById("h-ips-extra")?.value || "")
    .split(/\\r?\\n/).map(s => s.trim()).filter(Boolean);
  data.ips = data.ip ? [data.ip, ...extraIPs] : extraIPs;
  // aliases array
  data.aliases = (document.getElementById("h-aliases")?.value || "")
    .split(/\\r?\\n/).map(s => s.trim()).filter(Boolean);

  if (!data.hostname) { setMsg("主機名稱必填", "err"); return; }'''

if old_save_marker not in s:
    print("FAIL: heSave marker not found"); sys.exit(1)
s = s.replace(old_save_marker, new_save_marker, 1)
print("[+] heSave 加 ips/aliases pack")

with open(os.path.join(PATCH_DIR, "files", "webapp", "templates", "host_edit.html"), "w", encoding="utf-8") as f:
    f.write(s)
print(f"[+] 寫 host_edit.html ({len(s)} bytes)")

# ===== 2. dependency_service.py: topology 顯示優先 ips[0] =====
fp = os.path.join(WORK, "v3170_dep.py")
with open(fp, encoding="utf-8") as f:
    s2 = f.read()

old_ip = '''            "ip": h.get("ip", ""),'''
new_ip = '''            "ip": (h.get("ips") or [h.get("ip", "")])[0] if (h.get("ips") or h.get("ip")) else "",'''
if old_ip in s2:
    s2 = s2.replace(old_ip, new_ip, 1)
    with open(os.path.join(PATCH_DIR, "files", "webapp", "services", "dependency_service.py"), "w", encoding="utf-8") as f:
        f.write(s2)
    print(f"[+] dependency_service.py 拓撲 IP 顯示優先 ips[0]")
else:
    print("[!] 沒找到 dependency_service ip line, 不動")

# Python 語法 verify
import ast
ast.parse(s2)
print("[+] 全部 AST OK")
