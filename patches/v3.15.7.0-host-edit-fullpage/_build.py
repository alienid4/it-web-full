#!/usr/bin/env python3
"""Build v3.15.7.0 - 全頁主機編輯"""
import os, re, sys, shutil

WORK = r"C:\Users\User\AppData\Local\Temp\v3157"
PATCH_DIR = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.15.7.0-host-edit-fullpage"

# === app.py: 加 /admin/host-edit/<hostname> 與 /admin/host-edit/new 路由 ===
fp = os.path.join(WORK, "app.py")
with open(fp, encoding="utf-8") as f:
    s = f.read()

# 在 admin_page 之後加新路由
new_route = '''
@app.route("/admin/host-edit/new")
def admin_host_edit_new():
    return render_template("host_edit.html", hostname="", is_new=True)

@app.route("/admin/host-edit/<hostname>")
def admin_host_edit(hostname):
    return render_template("host_edit.html", hostname=hostname, is_new=False)

'''

marker = '''@app.route("/admin")
def admin_page():
    # oper（未登入）可瀏覽但操作受限，前端 JS 會控制
    return render_template("admin.html")

'''
if marker not in s:
    print("FAIL: admin_page marker not found in app.py")
    sys.exit(1)
if "admin_host_edit" in s:
    print("[skip] app.py 已有 admin_host_edit 路由")
else:
    s = s.replace(marker, marker + new_route)
    with open(fp, "w", encoding="utf-8") as f:
        f.write(s)
    print("[+] app.py 加 host-edit 路由")

# === admin.js: 改編輯 button 為新分頁連結 ===
fp = os.path.join(WORK, "admin.js")
with open(fp, encoding="utf-8") as f:
    js = f.read()

old_btn = '''html += '<button class="btn btn-sm" style="background:var(--g2);color:white;" onclick="editHost(\\''+hn+'\\')">編輯</button> ';'''
new_btn = '''html += '<a class="btn btn-sm" style="background:var(--g2);color:white;text-decoration:none;" href="/admin/host-edit/'+encodeURIComponent(hn)+'" target="_blank">📝 編輯</a> ';'''

if old_btn in js:
    js = js.replace(old_btn, new_btn)
    with open(fp, "w", encoding="utf-8") as f:
        f.write(js)
    print("[+] admin.js 編輯按鈕改新分頁連結")
else:
    print("[!] admin.js 找不到舊按鈕字串, 可能已替換過")

# === 複製到 patch dir ===
files_dir = os.path.join(PATCH_DIR, "files", "webapp")
shutil.copy(os.path.join(WORK, "app.py"), os.path.join(files_dir, "app.py"))
shutil.copy(os.path.join(WORK, "admin.js"), os.path.join(files_dir, "static", "js", "admin.js"))
print("[+] 已複製到 patch dir")

print()
print("檔案大小:")
for f in [
    os.path.join(files_dir, "app.py"),
    os.path.join(files_dir, "static", "js", "admin.js"),
    os.path.join(files_dir, "templates", "host_edit.html"),
]:
    print(f"  {os.path.basename(f):20} {os.path.getsize(f):>8} bytes")
