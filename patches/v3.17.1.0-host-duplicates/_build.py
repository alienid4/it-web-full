#!/usr/bin/env python3
"""Build v3.17.1.0 - 重複主機偵測"""
import os, re, sys

WORK = r"C:\Users\User\AppData\Local\Temp"
PATCH_DIR = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.17.1.0-host-duplicates"

# === 1. app.py: 加 /admin/host-duplicates route ===
fp = os.path.join(WORK, "v3171_app.py")
with open(fp, encoding="utf-8") as f: s = f.read()

if "host_duplicates" in s:
    print("[skip] app.py 已有 host_duplicates")
else:
    marker = '@app.route("/admin/host-edit/<hostname>")'
    if marker not in s:
        print("FAIL: marker not in app.py"); sys.exit(1)
    insert = '''@app.route("/admin/host-duplicates")
def admin_host_duplicates():
    return render_template("host_duplicates.html")


'''
    s = s.replace(marker, insert + marker)
    print("[+] app.py 加 host-duplicates route")

with open(os.path.join(PATCH_DIR, "files", "webapp", "app.py"), "w", encoding="utf-8") as f:
    f.write(s)

# === 2. api_admin.py: 加 GET duplicates + POST merge ===
fp = os.path.join(WORK, "v3171_api_admin.py")
with open(fp, encoding="utf-8") as f: s = f.read()

if "/hosts/duplicates" in s:
    print("[skip] api_admin.py 已有 duplicates")
else:
    # 找一個 anchor: ping_host endpoint 後面插
    marker = '@bp.route("/hosts/<hostname>/ping", methods=["POST"])'
    if marker not in s:
        print("FAIL: api_admin marker not found"); sys.exit(1)
    insert = '''@bp.route("/hosts/duplicates", methods=["GET"])
@admin_required
def hosts_duplicates():
    """v3.17.1.0+: 找出重複/相似主機 (Levenshtein + alias + 共用 IP)"""
    try:
        from services.host_dedup import find_similar_hosts
        pairs = find_similar_hosts()
        return jsonify({"success": True, "pairs": pairs})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@bp.route("/hosts/merge", methods=["POST"])
@admin_required
def hosts_merge():
    """v3.17.1.0+: 合併兩台主機"""
    try:
        from services.host_dedup import merge_hosts
        data = request.get_json(force=True)
        primary = data.get("primary")
        duplicate = data.get("duplicate")
        if not primary or not duplicate:
            return jsonify({"success": False, "error": "primary / duplicate 必填"}), 400
        ok, msg = merge_hosts(primary, duplicate)
        if ok:
            log_action(session["username"], "host_merge", f"合併 {duplicate} -> {primary}", request.remote_addr)
            return jsonify({"success": True, "message": msg})
        else:
            return jsonify({"success": False, "error": msg}), 400
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


'''
    s = s.replace(marker, insert + marker)
    print("[+] api_admin.py 加 duplicates + merge endpoints")

with open(os.path.join(PATCH_DIR, "files", "webapp", "routes", "api_admin.py"), "w", encoding="utf-8") as f:
    f.write(s)

# === 3. admin.html: 主機管理 toolbar 加按鈕 ===
fp = os.path.join(WORK, "v3171_admin.html")
with open(fp, encoding="utf-8") as f: s = f.read()

if "host-duplicates" in s:
    print("[skip] admin.html 已有按鈕")
else:
    # 找「新增主機」按鈕的附近加我們的按鈕
    marker = '<button class="btn btn-primary" onclick="showAddHostModal()">新增主機</button>'
    if marker not in s:
        print("FAIL: admin.html 找不到 marker"); sys.exit(1)
    insert = '<a class="btn" style="background:#f59e0b;color:#fff;text-decoration:none;margin-left:8px;" href="/admin/host-duplicates" target="_blank">🔍 重複偵測</a>\n      '
    # 在 「新增主機」 之後插
    btn = '<button class="btn btn-primary" onclick="showAddHostModal()">新增主機</button>'
    if btn in s:
        s = s.replace(btn, btn + "\n      " + insert)
        print("[+] admin.html 加 重複偵測 按鈕")
    else:
        print("[!] admin.html 找不到新增主機按鈕, 跳過 (使用者可直接打 /admin/host-duplicates URL)")

with open(os.path.join(PATCH_DIR, "files", "webapp", "templates", "admin.html"), "w", encoding="utf-8") as f:
    f.write(s)

# === Python 語法 verify ===
import ast
for f in [
    os.path.join(PATCH_DIR, "files", "webapp", "app.py"),
    os.path.join(PATCH_DIR, "files", "webapp", "routes", "api_admin.py"),
    os.path.join(PATCH_DIR, "files", "webapp", "services", "host_dedup.py"),
]:
    ast.parse(open(f, encoding="utf-8").read())
print("[+] Python AST 全部 OK")
