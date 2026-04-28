#!/usr/bin/env python3
"""Build v3.17.2.0 - 變更歷史 (P6)"""
import os, sys

WORK = r"C:\Users\User\AppData\Local\Temp"
PATCH_DIR = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.17.2.0-change-log"

# === app.py: 加 /admin/host-history/<hostname> route ===
fp = os.path.join(WORK, "v3172_app.py")
with open(fp, encoding="utf-8") as f: s = f.read()

if "host_history" not in s:
    marker = '@app.route("/admin/host-edit/<hostname>")'
    insert = '''@app.route("/admin/host-history/<hostname>")
def admin_host_history(hostname):
    return render_template("host_history.html", hostname=hostname)


'''
    s = s.replace(marker, insert + marker)
    print("[+] app.py 加 host-history route")
else:
    print("[skip] app.py 已有")

with open(os.path.join(PATCH_DIR, "files", "webapp", "app.py"), "w", encoding="utf-8") as f:
    f.write(s)

# === api_admin.py: 加 GET history + 自動寫 log 到既有 add/edit/delete/merge ===
fp = os.path.join(WORK, "v3172_api_admin.py")
with open(fp, encoding="utf-8") as f: s = f.read()

# 1) 加 GET /hosts/<hostname>/history endpoint
if "/hosts/<hostname>/history" not in s:
    marker = '@bp.route("/hosts/duplicates", methods=["GET"])'
    insert = '''@bp.route("/hosts/<hostname>/history", methods=["GET"])
@login_required
def hosts_history(hostname):
    """v3.17.2.0+: 取主機變更歷史"""
    try:
        from services.change_log import list_history
        return jsonify({"success": True, "history": list_history(hostname=hostname)})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


'''
    s = s.replace(marker, insert + marker)
    print("[+] api_admin.py 加 GET /hosts/<hn>/history")

# 2) 自動寫 log: add_host
old_add = '''def add_host():
    data = request.get_json(force=True)
    if not data.get("hostname"):
        return jsonify({"success": False, "error": "缺少 hostname 欄位"}), 400
    data["imported_at"] = datetime.now().isoformat()
    data["updated_at"] = datetime.now().isoformat()
    get_collection("hosts").update_one({"hostname": data["hostname"]}, {"$set": data}, upsert=True)
    # Also update hosts_config.json
    _sync_hosts_config()
    log_action(session["username"], "host_add", f"新增主機: {data['hostname']}", request.remote_addr)
    return jsonify({"success": True, "message": f"主機 {data['hostname']} 已新增"})'''
new_add = '''def add_host():
    data = request.get_json(force=True)
    if not data.get("hostname"):
        return jsonify({"success": False, "error": "缺少 hostname 欄位"}), 400
    data["imported_at"] = datetime.now().isoformat()
    data["updated_at"] = datetime.now().isoformat()
    hn = data["hostname"]
    existing = get_collection("hosts").find_one({"hostname": hn})
    get_collection("hosts").update_one({"hostname": hn}, {"$set": data}, upsert=True)
    # Also update hosts_config.json
    _sync_hosts_config()
    # v3.17.2.0+: 寫變更歷史
    try:
        from services.change_log import record
        record(hostname=hn, action="update" if existing else "create",
               who=session.get("username"), before=existing, after=data,
               detail=("更新主機" if existing else "新增主機") + ": " + hn)
    except Exception:
        pass
    log_action(session["username"], "host_add", f"新增主機: {hn}", request.remote_addr)
    return jsonify({"success": True, "message": f"主機 {hn} 已新增"})'''

if old_add in s:
    s = s.replace(old_add, new_add, 1)
    print("[+] api_admin.py add_host hook 變更歷史")

# 3) edit_host
old_edit = '''def edit_host(hostname):
    data = request.get_json(force=True)
    data["updated_at"] = datetime.now().isoformat()
    get_collection("hosts").update_one({"hostname": hostname}, {"$set": data})
    _sync_hosts_config()
    log_action(session["username"], "host_edit", f"編輯主機: {hostname}", request.remote_addr)
    return jsonify({"success": True})'''
new_edit = '''def edit_host(hostname):
    data = request.get_json(force=True)
    data["updated_at"] = datetime.now().isoformat()
    existing = get_collection("hosts").find_one({"hostname": hostname})
    get_collection("hosts").update_one({"hostname": hostname}, {"$set": data})
    _sync_hosts_config()
    # v3.17.2.0+: 寫變更歷史
    try:
        from services.change_log import record
        record(hostname=hostname, action="update",
               who=session.get("username"), before=existing, after={**(existing or {}), **data},
               detail="編輯主機: " + hostname)
    except Exception:
        pass
    log_action(session["username"], "host_edit", f"編輯主機: {hostname}", request.remote_addr)
    return jsonify({"success": True})'''
if old_edit in s:
    s = s.replace(old_edit, new_edit, 1)
    print("[+] api_admin.py edit_host hook 變更歷史")

# 4) delete_host
old_del = '''def delete_host(hostname):
    get_collection("hosts").delete_one({"hostname": hostname})
    _sync_hosts_config()
    log_action(session["username"], "host_delete", f"刪除主機: {hostname}", request.remote_addr)
    return jsonify({"success": True})'''
new_del = '''def delete_host(hostname):
    existing = get_collection("hosts").find_one({"hostname": hostname})
    get_collection("hosts").delete_one({"hostname": hostname})
    _sync_hosts_config()
    # v3.17.2.0+: 寫變更歷史
    try:
        from services.change_log import record
        record(hostname=hostname, action="delete",
               who=session.get("username"), before=existing, after=None,
               detail="刪除主機: " + hostname)
    except Exception:
        pass
    log_action(session["username"], "host_delete", f"刪除主機: {hostname}", request.remote_addr)
    return jsonify({"success": True})'''
if old_del in s:
    s = s.replace(old_del, new_del, 1)
    print("[+] api_admin.py delete_host hook 變更歷史")

# 5) merge hook (v3.17.1.0)
old_merge = '''        if ok:
            log_action(session["username"], "host_merge", f"合併 {duplicate} -> {primary}", request.remote_addr)
            return jsonify({"success": True, "message": msg})'''
new_merge = '''        if ok:
            try:
                from services.change_log import record
                record(hostname=primary, action="merge", who=session.get("username"),
                       before=None, after=None,
                       detail=f"合併 {duplicate} -> {primary}: {msg}")
                record(hostname=duplicate, action="delete", who=session.get("username"),
                       before=None, after=None,
                       detail=f"被合併進 {primary} (deleted)")
            except Exception:
                pass
            log_action(session["username"], "host_merge", f"合併 {duplicate} -> {primary}", request.remote_addr)
            return jsonify({"success": True, "message": msg})'''
if old_merge in s:
    s = s.replace(old_merge, new_merge, 1)
    print("[+] api_admin.py merge_hosts hook 變更歷史")

with open(os.path.join(PATCH_DIR, "files", "webapp", "routes", "api_admin.py"), "w", encoding="utf-8") as f:
    f.write(s)

# === Python 語法 verify ===
import ast
for f in [
    os.path.join(PATCH_DIR, "files", "webapp", "app.py"),
    os.path.join(PATCH_DIR, "files", "webapp", "routes", "api_admin.py"),
    os.path.join(PATCH_DIR, "files", "webapp", "services", "change_log.py"),
]:
    ast.parse(open(f, encoding="utf-8").read())
print("[+] AST OK")
