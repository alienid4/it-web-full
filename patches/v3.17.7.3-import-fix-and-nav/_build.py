#!/usr/bin/env python3
"""v3.17.7.3 - import_csv 加 29 中文 mapping + admin.js hash 隱藏 group + DELETE auto reload"""
import os, re, sys, ast

WORK = r"C:\Users\User\AppData\Local\Temp"
PATCH = r"C:\Users\User\OneDrive\2025 Data\AI LAB\claude code\patches\v3.17.7.3-import-fix-and-nav"

# ===== 1. api_admin.py: rewrite import_csv =====
fp = os.path.join(WORK, "v3173_api.py")
with open(fp, encoding="utf-8") as f:
    s = f.read()

# Find import_csv block and replace whole function (find by signature, end at next @bp.route)
m = re.search(r"@bp\.route\(\"/hosts/import-csv\", methods=\[\"POST\"\]\)\s*@admin_required\s*def import_csv\(\):[\s\S]*?(?=\n@bp\.route)", s)
if not m:
    print("FAIL: import_csv block not found")
    sys.exit(1)

new_func = '''@bp.route("/hosts/import-csv", methods=["POST"])
@admin_required
def import_csv():
    """v3.17.7.3+: 從 CSV 匯入主機 (接受 29 欄資產表中文標頭 + 9 巡檢欄)"""
    import csv, io
    if "file" not in request.files:
        raw = request.get_data(as_text=True)
        if not raw:
            return jsonify({"success": False, "error": "未提供檔案"}), 400
        reader = csv.DictReader(io.StringIO(raw))
    else:
        f = request.files["file"]
        raw_bytes = f.read()
        content = None
        for enc in ("utf-8-sig", "utf-8", "big5", "gbk"):
            try:
                content = raw_bytes.decode(enc)
                break
            except UnicodeDecodeError:
                continue
        if content is None:
            return jsonify({"success": False, "error": "CSV 解碼失敗"}), 400
        reader = csv.DictReader(io.StringIO(content))

    HEADER_MAP = {
        "盤點單位-處別": "division", "處別": "division", "處": "division", "division": "division",
        "盤點單位-部門": "department", "部門": "department", "department": "department",
        "資產序號": "asset_seq", "asset_seq": "asset_seq",
        "資產狀態": "status", "狀態": "status", "status": "status",
        "群組名稱": "group_name", "群組": "group_name", "group_name": "group_name",
        "APID": "apid", "apid": "apid",
        "資產名稱": "asset_name", "asset_name": "asset_name",
        "整體基礎架構": "device_type", "基礎架構": "device_type", "device_type": "device_type",
        "設備型號": "device_model", "device_model": "device_model",
        "資產用途": "asset_usage", "用途": "asset_usage", "asset_usage": "asset_usage",
        "資產實體位置": "location", "實體位置": "location", "位置": "location", "location": "location",
        "機櫃編號": "rack_no", "機櫃": "rack_no", "rack_no": "rack_no",
        "數量": "quantity", "quantity": "quantity",
        "擁有者": "owner", "owner": "owner",
        "環境別": "environment", "環境": "environment", "environment": "environment",
        "主機名稱": "hostname", "host": "hostname", "hostname": "hostname",
        "作業系統": "os", "OS": "os", "os": "os",
        "BIG IP/VIP": "bigip", "VIP": "bigip", "bigip": "bigip",
        "硬體編號": "hardware_seq", "hardware_seq": "hardware_seq",
        "IP位址": "ip", "IP": "ip", "ip": "ip",
        "保管者": "custodian", "custodian": "custodian",
        "系統管理者": "sys_admin", "sys_admin": "sys_admin",
        "使用者": "user", "user": "user",
        "附加說明": "note", "說明": "note", "備註": "note", "note": "note",
        "所屬公司": "company", "公司": "company", "company": "company",
        "機密性": "confidentiality", "confidentiality": "confidentiality",
        "完整性": "integrity", "integrity": "integrity",
        "可用性": "availability", "availability": "availability",
        "申請單編號": "request_no", "申請單號": "request_no", "request_no": "request_no",
        "OS Group": "os_group", "os_group": "os_group",
        "AD帳號": "custodian_ad", "保管者AD": "custodian_ad", "custodian_ad": "custodian_ad",
        "其他IP": "_ips_extra", "其他IP(分號分隔)": "_ips_extra",
        "別名": "_aliases", "別名(分號分隔)": "_aliases",
        "級別": "tier", "tier": "tier",
        "系統別": "system_name", "system_name": "system_name",
        "AP負責人": "ap_owner", "ap_owner": "ap_owner",
        "使用單位": "user_unit", "user_unit": "user_unit",
        "架構說明": "infra", "infra": "infra",
    }

    col = get_collection("hosts")
    count = 0
    errors = []
    for i, row in enumerate(reader):
        doc = {}
        for raw_k, raw_v in row.items():
            if raw_k is None:
                continue
            db_k = HEADER_MAP.get(raw_k.strip())
            if not db_k:
                continue
            v = (raw_v or "").strip() if isinstance(raw_v, str) else raw_v
            doc[db_k] = v
        hostname = (doc.get("hostname") or "").strip()
        if not hostname:
            errors.append("第 " + str(i + 2) + " 行缺少主機名稱")
            continue
        # ips/aliases 處理 (分號 or 逗號分隔)
        if "_ips_extra" in doc:
            extras = [x.strip() for x in str(doc.pop("_ips_extra")).replace(",", ";").split(";") if x.strip()]
            primary = (doc.get("ip") or "").strip()
            doc["ips"] = ([primary] + extras) if primary else extras
        if "_aliases" in doc:
            doc["aliases"] = [x.strip() for x in str(doc.pop("_aliases")).replace(",", ";").split(";") if x.strip()]
        # CIA / 數量 轉 int
        for k in ("confidentiality", "integrity", "availability", "quantity"):
            if k in doc and doc[k] not in (None, ""):
                try:
                    doc[k] = int(doc[k])
                except (ValueError, TypeError):
                    pass
        doc["status"] = doc.get("status") or "使用中"
        doc["has_python"] = True
        doc["imported_at"] = datetime.now().isoformat()
        doc["updated_at"] = datetime.now().isoformat()
        col.update_one({"hostname": hostname}, {"$set": doc}, upsert=True)
        count += 1

    _sync_hosts_config()
    log_action(session["username"], "import_csv", "CSV 匯入 " + str(count) + " 台主機", request.remote_addr)
    return jsonify({"success": True, "message": "成功匯入 " + str(count) + " 台主機", "count": count, "errors": errors})


'''

s = s[:m.start()] + new_func + s[m.end():]
ast.parse(s)
out = os.path.join(PATCH, "files", "webapp", "routes", "api_admin.py")
with open(out, "w", encoding="utf-8") as f:
    f.write(s)
print("[+] api_admin.py: import_csv rewrote, AST OK")

# ===== 2. admin.js: hash hide group + DELETE auto reload =====
fp = os.path.join(WORK, "v3173_admin.js")
with open(fp, encoding="utf-8") as f:
    js = f.read()

# 2-1: hash hide non-host group
marker = 'var btn = document.querySelector(\'.admin-tab[data-tab="\' + hash + \'"]\');\n    if (btn) btn.click();\n  }'
hide_code = '''var btn = document.querySelector('.admin-tab[data-tab="' + hash + '"]');
    if (btn) btn.click();
  }
  // v3.17.7.3+: hash = 主機管理 group → 隱藏其他 admin-nav-group
  var HOST_TABS = ["hosts","jobs","scheduler","alerts"];
  if (HOST_TABS.indexOf(hash) >= 0) {
    document.querySelectorAll(".admin-nav-group").forEach(function(g){
      var hasHostTab = false;
      g.querySelectorAll(".admin-tab[data-tab]").forEach(function(b){
        if (HOST_TABS.indexOf(b.getAttribute("data-tab")) >= 0) hasHostTab = true;
      });
      if (!hasHostTab) g.style.display = "none";
    });
  }'''

if marker in js:
    js = js.replace(marker, hide_code, 1)
    print("[+] admin.js: hash 隱藏 non-host group")
else:
    print("[!] admin.js hash marker 找不到 (檢查格式)")

# 2-2: DELETE host → reload
# 找 adminAction 內 success 處理, 加 reload
m2 = re.search(r"function adminAction\([\s\S]*?\n\}\s*\n", js)
if m2:
    block = m2.group(0)
    # 找 alert / toast 之類的 success line
    success_line = 'alert(res.message || "已執行")'
    if success_line in block:
        new_block = block.replace(
            success_line,
            success_line + ';\n      // v3.17.7.3+: DELETE host 後 auto reload\n      if (method === "DELETE" && url.indexOf("/hosts/") >= 0 && typeof loadHosts === "function") setTimeout(loadHosts, 200)'
        )
        js = js.replace(block, new_block, 1)
        print("[+] admin.js: adminAction DELETE host auto reload")
    else:
        # 找其他可能 pattern
        alt = '_dashToast && _dashToast'
        if alt in block:
            print("[!] adminAction 用 _dashToast (非 alert), 嘗試其他 pattern")

out = os.path.join(PATCH, "files", "webapp", "static", "js", "admin.js")
with open(out, "w", encoding="utf-8") as f:
    f.write(js)
print("[+] admin.js written")
