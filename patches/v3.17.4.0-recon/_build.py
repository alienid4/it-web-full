#!/usr/bin/env python3
"""Build v3.17.4.0 - Excel 對帳 (P4)"""
import os, sys
WORK = r"C:\Users\User\AppData\Local\Temp"
PATCH_DIR = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.17.4.0-recon"

# === app.py: /admin/recon ===
fp = os.path.join(WORK, "v3174_app.py")
with open(fp, encoding="utf-8") as f: s = f.read()
if "admin_recon" not in s:
    marker = '@app.route("/admin/host-edit/<hostname>")'
    insert = '''@app.route("/admin/recon")
def admin_recon():
    return render_template("recon.html")


'''
    s = s.replace(marker, insert + marker)
    print("[+] app.py 加 /admin/recon")
with open(os.path.join(PATCH_DIR, "files", "webapp", "app.py"), "w", encoding="utf-8") as f:
    f.write(s)

# === api_admin.py: POST /recon/upload ===
fp = os.path.join(WORK, "v3174_api_admin.py")
with open(fp, encoding="utf-8") as f: s = f.read()
if "/recon/upload" not in s:
    marker = '@bp.route("/subnets", methods=["GET"])'
    insert = '''@bp.route("/recon/upload", methods=["POST"])
@admin_required
def recon_upload():
    """v3.17.4.0+: 上傳 .xlsx / .csv 跟 hosts collection 對帳"""
    try:
        f = request.files.get("file")
        if not f:
            return jsonify({"success": False, "error": "缺少 file"}), 400
        from services.recon_service import parse_file, compare
        rows = parse_file(f.filename, f.read())
        result = compare(rows)
        return jsonify({"success": True, "result": result, "filename": f.filename})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


'''
    s = s.replace(marker, insert + marker)
    print("[+] api_admin.py 加 /recon/upload")
with open(os.path.join(PATCH_DIR, "files", "webapp", "routes", "api_admin.py"), "w", encoding="utf-8") as f:
    f.write(s)

# === base.html: navbar 加 對帳入口 ===
fp = os.path.join(WORK, "v3174_base.html")
with open(fp, encoding="utf-8") as f: s = f.read()
old = '<li><a href="/admin/subnets" id="nav-subnets">🌐 IPAM</a></li>'
new = '<li><a href="/admin/subnets" id="nav-subnets">🌐 IPAM</a></li>\n        <li><a href="/admin/recon" id="nav-recon">📊 對帳</a></li>'
if "nav-recon" not in s and old in s:
    s = s.replace(old, new, 1)
    print("[+] base.html navbar 加 對帳入口")
with open(os.path.join(PATCH_DIR, "files", "webapp", "templates", "base.html"), "w", encoding="utf-8") as f:
    f.write(s)

import ast
for f in [os.path.join(PATCH_DIR, "files", "webapp", "app.py"),
          os.path.join(PATCH_DIR, "files", "webapp", "routes", "api_admin.py"),
          os.path.join(PATCH_DIR, "files", "webapp", "services", "recon_service.py")]:
    ast.parse(open(f, encoding="utf-8").read())
print("[+] AST OK")
