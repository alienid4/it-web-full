#!/usr/bin/env python3
"""Build script for v3.15.6.0 — replace host-modal in admin.html + saveHost/editHost in admin.js"""
import sys, os

WORK = r"C:\Users\User\AppData\Local\Temp\v3156"
print(f"work dir: {WORK}")

# ============= admin.html: 替換 host-modal =============
fp = os.path.join(WORK, "admin.html")
with open(fp, encoding="utf-8") as f:
    content = f.read()

old_start_marker = '<!-- Add Host Modal -->\n<div class="modal-overlay" id="host-modal">'
old_end_marker = '<script src="/static/js/admin.js'
i_start = content.find(old_start_marker)
i_end = content.find(old_end_marker, i_start)
if i_start < 0 or i_end < 0:
    sys.exit(f"FAIL HTML: start={i_start} end={i_end}")

NEW_MODAL = """<!-- Add Host Modal (v3.15.6.0: 29 欄資產表 + scrollable) -->
<div class="modal-overlay" id="host-modal">
  <div class="modal" style="max-width:760px;max-height:88vh;overflow-y:auto;">
    <div class="modal-title" id="host-modal-title">新增主機</div>

    <h3 style="margin:16px 0 8px;color:var(--g1);border-bottom:1px solid #eee;padding-bottom:4px;">基本</h3>
    <div class="form-group"><label>主機名稱</label><input type="text" id="h-hostname"></div>
    <div class="form-group"><label>IP</label><input type="text" id="h-ip"></div>
    <div class="form-group"><label>作業系統</label><select id="h-os"><option value="Rocky Linux">Rocky Linux</option><option value="RHEL">RHEL</option><option value="Debian">Debian</option><option value="AIX">AIX</option><option value="Windows Server 2016">Windows Server 2016</option><option value="Windows Server 2019">Windows Server 2019</option><option value="Windows Server 2022">Windows Server 2022</option><option value="Cisco IOS">Cisco IOS (SNMP)</option><option value="Juniper">Juniper (SNMP)</option><option value="Fortinet">Fortinet (SNMP)</option><option value="Aruba">Aruba (SNMP)</option><option value="Network Device">網路設備 (SNMP)</option><option value="IBM AS/400">IBM AS/400 (SNMP)</option></select></div>
    <div class="form-group"><label>OS Group</label><select id="h-osgroup"><option value="rocky">rocky</option><option value="rhel">rhel</option><option value="debian">debian</option><option value="aix">aix</option><option value="windows">windows</option><option value="snmp">snmp (網路設備)</option><option value="as400">as400</option></select></div>
    <div class="form-group"><label>SNMP Community</label><input type="text" id="h-snmp-community" placeholder="預設: public(SNMP設備填寫)"></div>
    <div class="form-group"><label>環境別</label><select id="h-env"><option value="OA">OA</option><option value="正式">正式</option><option value="使用者測試(UAT)">使用者測試(UAT)</option><option value="備援">備援</option><option value="測試">測試</option><option value="開發環境(DEV)">開發環境(DEV)</option></select></div>
    <div class="form-group"><label>資產狀態</label><select id="h-status"><option value="使用中">使用中</option><option value="停用">停用</option><option value="報廢">報廢</option><option value="待退役">待退役</option></select></div>

    <h3 style="margin:16px 0 8px;color:var(--g1);border-bottom:1px solid #eee;padding-bottom:4px;">資產表</h3>
    <div class="form-group"><label>盤點單位-處別</label><input type="text" id="h-division" placeholder="例: 資訊管理處"></div>
    <div class="form-group"><label>盤點單位-部門</label><input type="text" id="h-department" placeholder="例: 資訊架構部"></div>
    <div class="form-group"><label>資產序號</label><input type="text" id="h-asset-seq" placeholder="HW-XXXXXXXX"></div>
    <div class="form-group"><label>群組名稱</label><select id="h-group-name"><option value="">未設定</option><option value="H1-第一類系統設備">H1-第一類系統設備</option><option value="H2-第二類系統設備">H2-第二類系統設備</option><option value="H3-第三類系統設備">H3-第三類系統設備</option><option value="H4-測試設備">H4-測試設備</option><option value="H5-關鍵網路設備">H5-關鍵網路設備</option><option value="H6-一般網路設備">H6-一般網路設備</option><option value="H7-基礎設備">H7-基礎設備</option><option value="H8-個人電腦及周邊設備">H8-個人電腦及周邊設備</option><option value="H9-IT 管理性系統設備">H9-IT 管理性系統設備</option></select></div>
    <div class="form-group"><label>APID</label><input type="text" id="h-apid" placeholder="例: 巡檢系統"></div>
    <div class="form-group"><label>資產名稱</label><input type="text" id="h-asset-name" placeholder="例: L-001"></div>
    <div class="form-group"><label>整體基礎架構</label><input type="text" id="h-device-type" placeholder="例: 地端資產 (VM)"></div>
    <div class="form-group"><label>設備型號</label><input type="text" id="h-device-model" placeholder="例: VMware VM / Dell R740"></div>
    <div class="form-group"><label>資產用途</label><input type="text" id="h-asset-usage" placeholder="例: AP Server"></div>
    <div class="form-group"><label>資產實體位置</label><input type="text" id="h-location" placeholder="例: LAB機房"></div>
    <div class="form-group"><label>機櫃編號</label><input type="text" id="h-rack-no" placeholder="例: R12"></div>
    <div class="form-group"><label>數量</label><input type="number" id="h-quantity" value="1" min="1"></div>
    <div class="form-group"><label>BIG IP/VIP</label><input type="text" id="h-bigip" placeholder="例: 無 / VIP-10.1.1.100"></div>
    <div class="form-group"><label>硬體編號</label><input type="text" id="h-hardware-seq" placeholder="例: VM-98765"></div>

    <h3 style="margin:16px 0 8px;color:var(--g1);border-bottom:1px solid #eee;padding-bottom:4px;">人員</h3>
    <div class="form-group"><label>擁有者</label><input type="text" id="h-owner" placeholder="例: 資訊架構部"></div>
    <div class="form-group"><label>保管者</label><input type="text" id="h-custodian"></div>
    <div class="form-group"><label>系統管理者</label><input type="text" id="h-sys-admin"></div>
    <div class="form-group"><label>使用者</label><input type="text" id="h-user" placeholder="例: lab-admin"></div>
    <div class="form-group"><label>使用單位</label><input type="text" id="h-user-unit" placeholder="例: 資訊架構部"></div>
    <div class="form-group"><label>AP 負責人</label><input type="text" id="h-ap-owner"></div>

    <h3 style="margin:16px 0 8px;color:var(--g1);border-bottom:1px solid #eee;padding-bottom:4px;">資安 / 公司 (CIA: 1=高/2=中/3=低)</h3>
    <div class="form-group"><label>所屬公司</label><input type="text" id="h-company" placeholder="例: 敦南總公司"></div>
    <div class="form-group"><label>機密性</label><select id="h-confidentiality"><option value="1">1 (高)</option><option value="2">2 (中)</option><option value="3">3 (低)</option></select></div>
    <div class="form-group"><label>完整性</label><select id="h-integrity"><option value="1">1 (高)</option><option value="2">2 (中)</option><option value="3">3 (低)</option></select></div>
    <div class="form-group"><label>可用性</label><select id="h-availability"><option value="1">1 (高)</option><option value="2">2 (中)</option><option value="3">3 (低)</option></select></div>
    <div class="form-group"><label>申請單編號</label><input type="text" id="h-request-no" placeholder="例: E000000000001"></div>

    <h3 style="margin:16px 0 8px;color:var(--g1);border-bottom:1px solid #eee;padding-bottom:4px;">巡檢專屬</h3>
    <div class="form-group"><label>級別 (tier)</label><select id="h-tier"><option value="">未設定</option><option value="金">金</option><option value="銀">銀</option><option value="銅">銅</option></select></div>
    <div class="form-group"><label>系統別 (system_name)</label><input type="text" id="h-system-name" placeholder="例: 巡檢系統"></div>
    <div class="form-group"><label>架構說明 (infra)</label><input type="text" id="h-infra" placeholder="例: LAB測試環境"></div>
    <div class="form-group"><label>群組 (legacy)</label><input type="text" id="h-group" placeholder="舊欄位,可留空"></div>
    <div class="form-group"><label>附加說明</label><textarea id="h-note" rows="3" style="width:100%;font-family:inherit;"></textarea></div>

    <div style="display:flex;gap:8px;justify-content:flex-end;margin-top:20px;border-top:1px solid #eee;padding-top:16px;">
      <button class="btn" style="background:var(--c4);" onclick="closeHostModal()">取消</button>
      <button class="btn btn-primary" onclick="saveHost()">儲存</button>
    </div>
  </div>
</div>

"""

content_new = content[:i_start] + NEW_MODAL + content[i_end:]
with open(fp, "w", encoding="utf-8") as f:
    f.write(content_new)
print(f"admin.html: modal replaced ({i_end - i_start} -> {len(NEW_MODAL)} bytes)")

# ============= admin.js: 替換 saveHost + editHost =============
fp = os.path.join(WORK, "admin.js")
with open(fp, encoding="utf-8") as f:
    js = f.read()

import re

# 替換 saveHost
new_save = """function saveHost() {
  var hn = document.getElementById("h-hostname").value;
  var isEdit = document.getElementById("h-hostname").readOnly;
  var V = function(id) { var el = document.getElementById(id); return el ? el.value : ""; };
  var data = {
    // 基本
    hostname: hn,
    ip: V("h-ip"),
    os: V("h-os"),
    os_group: V("h-osgroup"),
    snmp_community: V("h-snmp-community"),
    environment: V("h-env"),
    status: V("h-status") || "使用中",
    // 資產表
    division: V("h-division"),
    department: V("h-department"),
    asset_seq: V("h-asset-seq"),
    group_name: V("h-group-name"),
    apid: V("h-apid"),
    asset_name: V("h-asset-name"),
    device_type: V("h-device-type"),
    device_model: V("h-device-model"),
    asset_usage: V("h-asset-usage"),
    location: V("h-location"),
    rack_no: V("h-rack-no"),
    quantity: parseInt(V("h-quantity") || "1", 10),
    bigip: V("h-bigip"),
    hardware_seq: V("h-hardware-seq"),
    // 人員
    owner: V("h-owner"),
    custodian: V("h-custodian"),
    sys_admin: V("h-sys-admin"),
    user: V("h-user"),
    user_unit: V("h-user-unit"),
    ap_owner: V("h-ap-owner"),
    // 資安
    company: V("h-company"),
    confidentiality: parseInt(V("h-confidentiality") || "1", 10),
    integrity: parseInt(V("h-integrity") || "1", 10),
    availability: parseInt(V("h-availability") || "1", 10),
    request_no: V("h-request-no"),
    // 巡檢
    tier: V("h-tier"),
    system_name: V("h-system-name"),
    infra: V("h-infra"),
    group: V("h-group"),
    note: V("h-note"),
    has_python: true,
  };
  var url = isEdit ? "/api/admin/hosts/" + hn : "/api/admin/hosts";
  var method = isEdit ? "PUT" : "POST";
  fetch(url, {method:method, headers:{"Content-Type":"application/json"}, body:JSON.stringify(data)})
    .then(function(r){return r.json();}).then(function(res) {
      alert(res.message || "已儲存");
      closeHostModal();
      loadHosts();
    });
}"""

js = re.sub(
    r"function saveHost\(\) \{[\s\S]*?\n\}\n",
    new_save + "\n",
    js, count=1
)

# 替換 editHost
new_edit = """function editHost(hostname) {
  fetch("/api/hosts/"+hostname).then(function(r){return r.json();}).then(function(res) {
    if (!res.success) return;
    var h = res.data;
    var S = function(id, v) { var el = document.getElementById(id); if (el) el.value = (v == null ? "" : v); };
    // 基本
    S("h-hostname", h.hostname); document.getElementById("h-hostname").readOnly = true;
    S("h-ip", h.ip);
    S("h-os", h.os);
    S("h-osgroup", h.os_group);
    S("h-snmp-community", h.snmp_community);
    S("h-env", h.environment);
    S("h-status", h.status || "使用中");
    // 資產表
    S("h-division", h.division);
    S("h-department", h.department);
    S("h-asset-seq", h.asset_seq);
    S("h-group-name", h.group_name);
    S("h-apid", h.apid);
    S("h-asset-name", h.asset_name);
    S("h-device-type", h.device_type);
    S("h-device-model", h.device_model);
    S("h-asset-usage", h.asset_usage);
    S("h-location", h.location);
    S("h-rack-no", h.rack_no);
    S("h-quantity", h.quantity || 1);
    S("h-bigip", h.bigip);
    S("h-hardware-seq", h.hardware_seq);
    // 人員
    S("h-owner", h.owner);
    S("h-custodian", h.custodian);
    S("h-sys-admin", h.sys_admin);
    S("h-user", h.user);
    S("h-user-unit", h.user_unit);
    S("h-ap-owner", h.ap_owner);
    // 資安
    S("h-company", h.company);
    S("h-confidentiality", h.confidentiality || 1);
    S("h-integrity", h.integrity || 1);
    S("h-availability", h.availability || 1);
    S("h-request-no", h.request_no);
    // 巡檢
    S("h-tier", h.tier);
    S("h-system-name", h.system_name);
    S("h-infra", h.infra);
    S("h-group", h.group);
    S("h-note", h.note);
    document.getElementById("host-modal-title").textContent = "編輯主機 - " + hostname;
    document.getElementById("host-modal").classList.add("active");
  });
}"""

js = re.sub(
    r"function editHost\(hostname\) \{[\s\S]*?\n\}\n",
    new_edit + "\n",
    js, count=1
)

# 同時提供 closeHostModal + 開新主機時清空 (確保 readOnly = false)
# 這部分如果原本 admin.js 已有 openHostModal/closeHostModal, 不動

with open(fp, "w", encoding="utf-8") as f:
    f.write(js)
print(f"admin.js: saveHost + editHost replaced")
