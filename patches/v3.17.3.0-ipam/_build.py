#!/usr/bin/env python3
"""Build v3.17.3.0 - IPAM 簡化版 (P3)"""
import os, sys

WORK = r"C:\Users\User\AppData\Local\Temp"
PATCH_DIR = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.17.3.0-ipam"

# === app.py: 加 /admin/subnets route ===
fp = os.path.join(WORK, "v3173_app.py")
with open(fp, encoding="utf-8") as f: s = f.read()
if "subnets" in s:
    print("[skip] app.py 已有 subnets")
else:
    marker = '@app.route("/admin/host-edit/<hostname>")'
    insert = '''@app.route("/admin/subnets")
def admin_subnets():
    return render_template("subnets.html")


'''
    s = s.replace(marker, insert + marker)
    print("[+] app.py 加 /admin/subnets")
with open(os.path.join(PATCH_DIR, "files", "webapp", "app.py"), "w", encoding="utf-8") as f:
    f.write(s)

# === api_admin.py: 加 subnets CRUD ===
fp = os.path.join(WORK, "v3173_api_admin.py")
with open(fp, encoding="utf-8") as f: s = f.read()
if "/subnets" in s:
    print("[skip] api_admin.py 已有 subnets")
else:
    marker = '@bp.route("/hosts/<hostname>/history", methods=["GET"])'
    insert = '''@bp.route("/subnets", methods=["GET"])
@login_required
def list_subnets_api():
    try:
        from services.subnet_service import list_subnets
        return jsonify({"success": True, "subnets": list_subnets()})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@bp.route("/subnets", methods=["POST"])
@admin_required
def create_subnet_api():
    try:
        from services.subnet_service import create_subnet
        data = request.get_json(force=True)
        ok, msg = create_subnet(data, who=session.get("username"))
        return (jsonify({"success": True, "message": msg}) if ok else
                (jsonify({"success": False, "error": msg}), 400))
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@bp.route("/subnets/<path:cidr>", methods=["GET"])
@login_required
def get_subnet_api(cidr):
    try:
        from services.subnet_service import get_subnet, next_available_ip
        s = get_subnet(cidr)
        if not s:
            return jsonify({"success": False, "error": "not found"}), 404
        return jsonify({"success": True, "subnet": s, "next_ip": next_available_ip(cidr)})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@bp.route("/subnets/<path:cidr>", methods=["PUT"])
@admin_required
def update_subnet_api(cidr):
    try:
        from services.subnet_service import update_subnet
        data = request.get_json(force=True)
        ok, msg = update_subnet(cidr, data, who=session.get("username"))
        return (jsonify({"success": True, "message": msg}) if ok else
                (jsonify({"success": False, "error": msg}), 400))
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@bp.route("/subnets/<path:cidr>", methods=["DELETE"])
@admin_required
def delete_subnet_api(cidr):
    try:
        from services.subnet_service import delete_subnet
        ok, msg = delete_subnet(cidr)
        return (jsonify({"success": True, "message": msg}) if ok else
                (jsonify({"success": False, "error": msg}), 404))
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


'''
    s = s.replace(marker, insert + marker)
    print("[+] api_admin.py 加 5 個 subnets CRUD")
with open(os.path.join(PATCH_DIR, "files", "webapp", "routes", "api_admin.py"), "w", encoding="utf-8") as f:
    f.write(s)

# === base.html navbar 加 IPAM 入口 (放在系統管理之前) ===
fp = os.path.join(WORK, "v3173_base.html")
with open(fp, encoding="utf-8") as f: s = f.read()

old_nav = '''<li><a href="/admin" id="nav-admin" style="color:var(--orange);">系統管理</a></li>'''
new_nav = '''<li><a href="/admin/subnets" id="nav-subnets">🌐 IPAM</a></li>
        <li><a href="/admin" id="nav-admin" style="color:var(--orange);">系統管理</a></li>'''
if "nav-subnets" not in s and old_nav in s:
    s = s.replace(old_nav, new_nav, 1)
    print("[+] base.html navbar 加 IPAM 入口")
else:
    print("[skip] base.html nav-subnets 已有 or marker not found")

with open(os.path.join(PATCH_DIR, "files", "webapp", "templates", "base.html"), "w", encoding="utf-8") as f:
    f.write(s)

# AST verify
import ast
for f in [
    os.path.join(PATCH_DIR, "files", "webapp", "app.py"),
    os.path.join(PATCH_DIR, "files", "webapp", "routes", "api_admin.py"),
    os.path.join(PATCH_DIR, "files", "webapp", "services", "subnet_service.py"),
]:
    ast.parse(open(f, encoding="utf-8").read())
print("[+] AST OK")
