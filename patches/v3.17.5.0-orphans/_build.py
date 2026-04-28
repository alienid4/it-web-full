#!/usr/bin/env python3
"""Build v3.17.5.0 - 孤兒主機 (P5)"""
import os, sys
WORK = r"C:\Users\User\AppData\Local\Temp"
PATCH_DIR = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.17.5.0-orphans"

# === app.py ===
fp = os.path.join(WORK, "v3175_app.py")
with open(fp, encoding="utf-8") as f: s = f.read()
if "admin_orphans" not in s:
    marker = '@app.route("/admin/host-edit/<hostname>")'
    insert = '''@app.route("/admin/orphans")
def admin_orphans():
    return render_template("orphans.html")


'''
    s = s.replace(marker, insert + marker)
    print("[+] app.py 加 /admin/orphans")
with open(os.path.join(PATCH_DIR, "files", "webapp", "app.py"), "w", encoding="utf-8") as f:
    f.write(s)

# === api_admin.py: GET /orphans/audit ===
fp = os.path.join(WORK, "v3175_api_admin.py")
with open(fp, encoding="utf-8") as f: s = f.read()
if "/orphans/audit" not in s:
    marker = '@bp.route("/recon/upload", methods=["POST"])'
    insert = '''@bp.route("/orphans/audit", methods=["GET"])
@login_required
def orphans_audit():
    """v3.17.5.0+: 孤兒主機 / 稽核曝光總覽"""
    try:
        from services.orphan_service import audit_summary
        days = int(request.args.get("days", 30))
        return jsonify({"success": True, "audit": audit_summary(days_threshold=days)})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


'''
    s = s.replace(marker, insert + marker)
    print("[+] api_admin.py 加 /orphans/audit")
with open(os.path.join(PATCH_DIR, "files", "webapp", "routes", "api_admin.py"), "w", encoding="utf-8") as f:
    f.write(s)

# === base.html: navbar 加 孤兒 入口 ===
fp = os.path.join(WORK, "v3175_base.html")
with open(fp, encoding="utf-8") as f: s = f.read()
old = '<li><a href="/admin/recon" id="nav-recon">📊 對帳</a></li>'
new = '<li><a href="/admin/recon" id="nav-recon">📊 對帳</a></li>\n        <li><a href="/admin/orphans" id="nav-orphans">👻 孤兒</a></li>'
if "nav-orphans" not in s and old in s:
    s = s.replace(old, new, 1)
    print("[+] base.html navbar 加 孤兒")
with open(os.path.join(PATCH_DIR, "files", "webapp", "templates", "base.html"), "w", encoding="utf-8") as f:
    f.write(s)

import ast
for f in [os.path.join(PATCH_DIR, "files", "webapp", "app.py"),
          os.path.join(PATCH_DIR, "files", "webapp", "routes", "api_admin.py"),
          os.path.join(PATCH_DIR, "files", "webapp", "services", "orphan_service.py")]:
    ast.parse(open(f, encoding="utf-8").read())
print("[+] AST OK")
