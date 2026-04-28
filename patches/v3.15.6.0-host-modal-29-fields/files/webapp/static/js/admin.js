** WARNING: connection is not using a post-quantum key exchange algorithm.
** This session may be vulnerable to "store now, decrypt later" attacks.
** The server may need to be upgraded. See https://openssh.com/pq.html
/* Admin Panel JavaScript */

// Tab switching
document.addEventListener("DOMContentLoaded", function() {
  // Check auth
  fetch("/api/admin/me").then(function(r){return r.json();}).then(function(res) {
    if (!res.success) { location.href = "/login"; return; }
    document.getElementById("admin-user").textContent = res.data.display_name + " (" + res.data.role + ")";
    loadTab("dashboard");
  }).catch(function(){ location.href = "/login"; });

  // Tab click handlers
  document.querySelectorAll(".admin-tab").forEach(function(btn) {
    btn.addEventListener("click", function() {
      document.querySelectorAll(".admin-tab").forEach(function(b){b.classList.remove("active");});
      document.querySelectorAll(".tab-panel").forEach(function(p){p.classList.remove("active");});
      btn.classList.add("active");
      var tab = btn.getAttribute("data-tab");
      document.getElementById("tab-" + tab).classList.add("active");
      loadTab(tab);
      history.replaceState(null, "", "/admin#" + tab);
    });
  });

  // Hash-based tab restore
  var hash = location.hash.replace("#", "");
  if (hash) {
    var btn = document.querySelector('.admin-tab[data-tab="' + hash + '"]');
    if (btn) btn.click();
  }

  // Set default month
  var now = new Date();
  var monthEl = document.getElementById("report-month");
  if (monthEl) monthEl.value = now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0");
});

var _tabLoaded = {};
function loadTab(tab) {
  if (_tabLoaded[tab]) return;
  _tabLoaded[tab] = true;
  var loaders = {
    "dashboard": loadDashboardTab,
    "settings": loadSettingsTab,
    "backups": loadBackupsTab,
    "jobs": loadJobsTab,
    "logs": function(){},
    "hosts": loadHostsTab,
    "alerts": loadAlertsTab,
    "scheduler": loadSchedulerTab,
    "perf-mgmt": function(){ if (typeof loadNmonSchedule === "function") loadNmonSchedule(); },
    "reports": function(){},
    "audit": loadAuditTab,
    "acctmgmt": loadAcctMgmtTab,
    "worklog": loadWorklogTab,
    "security-audit": loadSecurityAuditTab,
    "linux-init": loadLinuxInitTab,
    "ssh-keys": loadSSHKeysTab,
    "dependencies-mgmt": loadDependenciesMgmtTab,
  };
  if (loaders[tab]) loaders[tab]();
}

function doLogout() {
  fetch("/api/admin/logout", {method:"POST"}).then(function(){ location.href = "/login"; });
}

// Phase 2 #7B: async-feedback 標準化
// 通用 admin 後端操作 helper（全站 28+ 顆按鈕共用，改這裡一次修全部）
async function adminAction(url, method, confirmMsg) {
  if (confirmMsg && !confirm(confirmMsg)) return;
  var controller = new AbortController();
  var timeoutId = setTimeout(function(){ controller.abort(); }, 60000);
  try {
    var r = await fetch(url, {
      method: method,
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify({}),
      signal: controller.signal
    });
    var res = await r.json();
    var okText = res.message || res.output || "完成";
    if (res.success === false || res.error) {
      var errText = res.error || res.message || "執行失敗";
      if (typeof _dashToast === "function") _dashToast("\u2717 " + errText, "error");
      else alert("\u2717 " + errText);
    } else {
      if (typeof _dashToast === "function") _dashToast("\u2713 " + okText, "success");
      else alert("\u2713 " + okText);
    }
    _tabLoaded = {};
  } catch(e) {
    var emsg = (e.name === "AbortError") ? "請求逾時（超過 60 秒）" : (e.message || "未知錯誤");
    if (typeof _dashToast === "function") _dashToast("\u2717 " + emsg, "error");
    else alert("\u2717 " + emsg);
  } finally {
    clearTimeout(timeoutId);
  }
}

// === Dashboard Tab ===
function loadDashboardTab() {
  fetch("/api/admin/system/status").then(function(r){return r.json();}).then(function(res) {
    if (!res.success) return;
    var d = res.data;
    var kpi = document.getElementById("sys-kpi");
    kpi.className = "admin-kpi";
    kpi.innerHTML =
      '<div class="admin-kpi-item"><div class="admin-kpi-value" style="color:var(--g1);">'+d.flask.status+'</div><div class="admin-kpi-label">Flask</div></div>' +
      '<div class="admin-kpi-item"><div class="admin-kpi-value" style="color:'+(d.mongodb.status==="running"?"var(--g1)":"var(--red)")+';">'+d.mongodb.status+'</div><div class="admin-kpi-label">MongoDB</div></div>' +
      '<div class="admin-kpi-item"><div class="admin-kpi-value">'+d.disk.root.percent+'%</div><div class="admin-kpi-label">磁碟 / ('+d.disk.root.free_gb+'GB free)</div></div>' +
      '<div class="admin-kpi-item"><div class="admin-kpi-value">'+d.containers.length+'</div><div class="admin-kpi-label">容器</div></div>';
  });
  fetch("/api/admin/system/info").then(function(r){return r.json();}).then(function(res) {
    if (!res.success) return;
    var d = res.data;
    var html = '<table style="width:100%;"><tbody>';
    html += '<tr><td style="font-weight:500;width:120px;">主機名稱</td><td>'+d.hostname+'</td></tr>';
    html += '<tr><td style="font-weight:500;">IP</td><td>'+d.ip+'</td></tr>';
    html += '<tr><td style="font-weight:500;">作業系統</td><td>'+d.os+'</td></tr>';
    html += '<tr><td style="font-weight:500;">Python</td><td>'+d.python+'</td></tr>';
    html += '<tr><td style="font-weight:500;">Ansible</td><td>'+d.ansible+'</td></tr>';
    html += '<tr><td style="font-weight:500;">開機時間</td><td>'+d.boot_time+'</td></tr>';
    html += '<tr><td style="font-weight:500;">運行時長</td><td>'+d.uptime+'</td></tr>';
    html += '</tbody></table>';
    document.getElementById("sys-info").innerHTML = html;
  });
  // 在線使用者
  loadOnlineUsers();
}

function loadOnlineUsers() {
  fetch("/api/admin/online-users").then(function(r){return r.json();}).then(function(res) {
    if (!res.success) return;
    var countEl = document.getElementById("online-count");
    countEl.textContent = "(" + res.online_count + " 人在線 / " + res.total + " 人)";
    var container = document.getElementById("online-users");
    if (!res.data.length) { container.innerHTML = '<span style="color:var(--c3);font-size:13px;">無使用者紀錄</span>'; return; }
    var html = '<div style="display:flex;flex-wrap:wrap;gap:8px;">';
    res.data.forEach(function(u) {
      var isOnline = u.status === "online";
      var dot = isOnline ? "#4caf50" : "#bdbdbd";
      var bg = isOnline ? "#e8f5e9" : "#f5f5f5";
      var border = isOnline ? "#a5d6a7" : "#e0e0e0";
      var timeText = isOnline ? (u.minutes_ago <= 1 ? "剛剛" : u.minutes_ago + " 分鐘前") : u.last_seen;
      html += '<div style="display:flex;align-items:center;gap:8px;padding:6px 12px;border-radius:8px;background:' + bg + ';border:1px solid ' + border + ';font-size:13px;">';
      html += '<span style="width:8px;height:8px;border-radius:50%;background:' + dot + ';display:inline-block;"></span>';
      html += '<span style="font-weight:600;">' + (u.display_name || u.username) + '</span>';
      html += '<span style="color:var(--c3);font-size:11px;">(' + u.role + ')</span>';
      html += '<span style="color:var(--c3);font-size:11px;margin-left:4px;">' + timeText + '</span>';
      if (u.last_ip) html += '<span style="color:var(--c3);font-size:10px;font-family:monospace;">' + u.last_ip + '</span>';
      html += '</div>';
    });
    html += '</div>';
    container.innerHTML = html;
  }).catch(function(){ document.getElementById("online-users").innerHTML = '<span style="color:var(--c3);">載入失敗</span>'; });
}

// === Settings Tab ===
function loadSettingsTab() {
  fetch("/api/admin/settings").then(function(r){return r.json();}).then(function(res) {
    if (!res.success) return;
    var d = res.data;
    // Thresholds
    var th = d.thresholds || {};
    var thHtml = '<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px;">';
    ["disk","cpu","mem"].forEach(function(t) {
      thHtml += '<div class="form-group"><label>'+t.toUpperCase()+' 警告 (%)</label><input type="number" id="th-'+t+'-warn" value="'+(th[t+"_warn"]||"")+'"></div>';
      thHtml += '<div class="form-group"><label>'+t.toUpperCase()+' 嚴重 (%)</label><input type="number" id="th-'+t+'-crit" value="'+(th[t+"_crit"]||"")+'"></div>';
    });
    thHtml += '</div><button class="btn btn-primary" onclick="saveThresholds()">儲存閾值</button>';
    document.getElementById("settings-thresholds").innerHTML = thHtml;
    // Services
    var svcs = d.service_check_list || [];
    document.getElementById("settings-services").innerHTML =
      '<div id="svc-list">' + svcs.map(function(s){return '<span class="badge badge-ok" style="margin:2px;">'+s+' <a href="#" onclick="removeSvc(\''+s+'\');return false;" style="color:var(--red);margin-left:4px;">x</a></span>';}).join(" ") + '</div>' +
      '<div style="margin-top:8px;display:flex;gap:8px;"><input type="text" id="new-svc" placeholder="新增服務名稱" style="width:200px;"><button class="btn btn-sm btn-primary" onclick="addSvc()">新增</button></div>';
    // Disk exclusions
    var excl = d.disk_exclude_mounts || [];
    document.getElementById("settings-disk-excl").innerHTML =
      excl.map(function(e){return '<span class="badge" style="background:var(--bg);margin:2px;">'+e+'</span>';}).join(" ") +
      '<div style="font-size:12px;color:var(--c3);margin-top:8px;">排除前綴: ' + (d.disk_exclude_prefixes||[]).join(", ") + '</div>';
    // Email
    var email = d.notify_email || {};
    document.getElementById("settings-email").innerHTML =
      '<div class="form-group"><label>SMTP</label><input type="text" value="'+(email.smtp_host||"")+'" disabled></div>' +
      '<div class="form-group"><label>收件人</label><input type="text" id="email-to" value="'+((email.to||[]).join(", "))+'"></div>' +
      '<div class="form-group"><label>觸發條件</label><input type="text" id="email-on" value="'+((email.send_on||[]).join(", "))+'"></div>' +
      '<button class="btn btn-primary" onclick="saveEmail()">儲存通知設定</button>';
  });
}

function saveThresholds() {
  var th = {};
  ["disk","cpu","mem"].forEach(function(t) {
    th[t+"_warn"] = parseInt(document.getElementById("th-"+t+"-warn").value) || 0;
    th[t+"_crit"] = parseInt(document.getElementById("th-"+t+"-crit").value) || 0;
  });
  fetch("/api/admin/settings/thresholds", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({value:th})})
    .then(function(r){return r.json();}).then(function(res){alert(res.message||"已儲存");});
}

function addSvc() {
  var name = document.getElementById("new-svc").value.trim();
  if (!name) return;
  fetch("/api/admin/settings").then(function(r){return r.json();}).then(function(res) {
    var list = res.data.service_check_list || [];
    if (list.indexOf(name) === -1) list.push(name);
    return fetch("/api/admin/settings/service_check_list", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({value:list})});
  }).then(function(){_tabLoaded.settings=false;loadSettingsTab();});
}

function removeSvc(name) {
  fetch("/api/admin/settings").then(function(r){return r.json();}).then(function(res) {
    var list = (res.data.service_check_list || []).filter(function(s){return s!==name;});
    return fetch("/api/admin/settings/service_check_list", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({value:list})});
  }).then(function(){_tabLoaded.settings=false;loadSettingsTab();});
}

function saveEmail() {
  var to = document.getElementById("email-to").value.split(",").map(function(s){return s.trim();});
  var on = document.getElementById("email-on").value.split(",").map(function(s){return s.trim();});
  fetch("/api/admin/settings").then(function(r){return r.json();}).then(function(res) {
    var email = res.data.notify_email || {};
    email.to = to;
    email.send_on = on;
    return fetch("/api/admin/settings/notify_email", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({value:email})});
  }).then(function(){alert("已儲存");});
}

// === Backups Tab ===
function loadBackupsTab() {
  fetch("/api/admin/backups").then(function(r){return r.json();}).then(function(res) {
    if (!res.success || !res.data.length) {
      document.getElementById("backup-list").innerHTML = '<div class="no-data">無備份</div>';
      return;
    }
    var html = '<table style="width:100%;"><thead><tr><th>檔案名稱</th><th>大小</th><th>建立時間</th><th>操作</th></tr></thead><tbody>';
    res.data.forEach(function(b) {
      html += '<tr><td style="font-family:JetBrains Mono;font-size:12px;">'+b.name+'</td><td>'+b.size_mb+' MB</td><td>'+b.created.replace("T"," ").substring(0,19)+'</td>';
      html += '<td><button class="btn btn-sm btn-primary" onclick="adminAction(\'/api/admin/backups/'+b.name+'/restore\',\'POST\',\'確定要還原此備份？目前的資料會被覆蓋！\')">還原</button> ';
      html += '<button class="btn btn-sm btn-danger" onclick="adminAction(\'/api/admin/backups/'+b.name+'\',\'DELETE\',\'確定要刪除此備份？\')">刪除</button></td></tr>';
    });
    html += '</tbody></table>';
    document.getElementById("backup-list").innerHTML = html;
  });
}

function createBackup() {
  adminAction("/api/admin/backups", "POST", "確定要建立備份？");
  setTimeout(function(){_tabLoaded.backups=false;loadBackupsTab();}, 3000);
}

// === Jobs Tab ===
function loadJobsTab() {
  fetch("/api/admin/jobs/status").then(function(r){return r.json();}).then(function(res) {
    if (!res.success) return;
    var d = res.data;
    document.getElementById("job-status").innerHTML = d.last_run ? '<span class="badge badge-ok">最近執行: '+d.last_run+'</span>' : '<span class="badge badge-warn">尚無執行紀錄</span>';
    document.getElementById("job-log").textContent = (d.log_tail||[]).join("\n") || "無日誌";
  });
}

// === Logs Tab ===
function loadLogs() {
  var date = document.getElementById("log-date").value;
  var keyword = document.getElementById("log-keyword").value;
  fetch("/api/admin/logs/inspection?date="+date+"&keyword="+encodeURIComponent(keyword)+"&tail=200")
    .then(function(r){return r.json();}).then(function(res) {
      document.getElementById("log-content").textContent = (res.data||[]).map(function(l){return "["+l.file+"] "+l.line;}).join("\n") || "無符合的日誌";
    });
}

function loadFlaskLog() {
  fetch("/api/admin/logs/flask?tail=200").then(function(r){return r.json();}).then(function(res) {
    document.getElementById("log-content").textContent = (res.data||[]).join("\n") || "Flask log 為空";
  });
}

// === Hosts Tab ===
function loadHostsTab() {
  fetch("/api/hosts?per_page=200").then(function(r){return r.json();}).then(function(res) {
    var data = res.data || [];
    if (!data.length) {
      document.getElementById("admin-hosts-list").innerHTML = '<div class="no-data">無主機</div>';
      return;
    }
    var html = '<table style="width:100%;"><thead><tr><th>主機</th><th>IP</th><th>OS</th><th>環境</th><th>保管者</th><th>部門</th><th>群組</th><th>操作</th></tr></thead><tbody>';
    data.forEach(function(h) {
      var hn = h.hostname;
      html += '<tr id="row-'+hn+'">';
      html += '<td><strong>'+hn+'</strong></td>';
      html += '<td>'+h.ip+'</td>';
      html += '<td>'+(h.os||"-")+'</td>';
      html += '<td>'+(h.environment||"-")+'</td>';
      html += '<td id="custodian-'+hn+'">'+(h.custodian||"-")+'</td>';
      html += '<td id="dept-'+hn+'">'+(h.department||"-")+'</td>';
      html += '<td id="group-'+hn+'">'+(h.group||"-")+'</td>';
      html += '<td style="white-space:nowrap;">';
      html += '<button class="btn btn-sm" style="background:var(--g2);color:white;" onclick="editHost(\''+hn+'\')">編輯</button> ';
      html += '<button class="btn btn-sm" style="background:var(--g1);color:white;" onclick="pingHost(\''+hn+'\')">Ping</button> ';
      html += '<button class="btn btn-sm btn-danger" onclick="adminAction(\'/api/admin/hosts/'+hn+'\',\'DELETE\',\'確定要刪除 '+hn+'？\')">刪除</button>';
      html += '</td></tr>';
    });
    html += '</tbody></table>';
    document.getElementById("admin-hosts-list").innerHTML = html;
  });
}

function editHost(hostname) {
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
}

function uploadCSV(input) {
  if (!input.files.length) return;
  var formData = new FormData();
  formData.append("file", input.files[0]);
  fetch("/api/admin/hosts/import-csv", {method:"POST", body:formData})
    .then(function(r){return r.json();}).then(function(res) {
      var msg = res.message || "";
      if (res.errors && res.errors.length) msg += "\n\n警告:\n" + res.errors.join("\n");
      alert(msg);
      input.value = "";
      _tabLoaded.hosts = false;
      loadHostsTab();
    });
}

function importJson() {
  if (!confirm("確定從 hosts_config.json 重新匯入？")) return;
  fetch("/api/admin/hosts/import-json", {method:"POST"})
    .then(function(r){return r.json();}).then(function(res) {
      alert(res.message || "匯入完成");
      _tabLoaded.hosts = false;
      loadHostsTab();
    });
}

function pingHost(hostname) {
  fetch("/api/admin/hosts/"+hostname+"/ping", {method:"POST"})
    .then(function(r){return r.json();}).then(function(res) {
      alert(res.reachable ? hostname + " 連線成功！" : hostname + " 無法連線\n" + res.output);
    });
}

function showAddHostModal() {
  document.getElementById("h-hostname").value = "";
  document.getElementById("h-hostname").readOnly = false;
  document.getElementById("h-ip").value = "";
  document.getElementById("h-custodian").value = "";
  document.getElementById("h-dept").value = "";
  document.getElementById("h-group").value = "";
  document.getElementById("host-modal-title").textContent = "新增主機";
  document.getElementById("host-modal").classList.add("active");
}
function closeHostModal() { document.getElementById("host-modal").classList.remove("active"); }
function saveHost() {
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
}

// === Alerts Tab ===
function loadAlertsTab() {
  fetch("/api/admin/alerts").then(function(r){return r.json();}).then(function(res) {
    var data = res.data || [];
    if (!data.length) {
      document.getElementById("alert-list").innerHTML = '<div class="no-data">無告警紀錄</div>';
      return;
    }
    var html = '<table style="width:100%;"><thead><tr><th>主機</th><th>狀態</th><th>日期</th><th>時間</th><th>確認</th></tr></thead><tbody>';
    data.forEach(function(a) {
      var ackBadge = a.acknowledged ? '<span class="badge badge-ok">已確認 ('+a.ack_by+')</span>' : '<button class="btn btn-sm btn-primary" onclick="ackAlert(\''+a.hostname+'\',\''+a.run_date+'\',\''+a.run_time+'\')">確認</button>';
      html += '<tr><td><a href="/report/'+a.hostname+'" style="color:var(--g2);font-weight:700;">'+a.hostname+'</a></td><td><span class="badge badge-'+a.overall_status+'">'+a.overall_status+'</span></td><td>'+a.run_date+'</td><td>'+a.run_time+'</td><td>'+ackBadge+'</td></tr>';
    });
    html += '</tbody></table>';
    document.getElementById("alert-list").innerHTML = html;
  });
}

function ackAlert(hostname, date, time) {
  fetch("/api/admin/alerts/"+hostname+"/"+date+"/"+time+"/ack", {method:"PUT"})
    .then(function(){_tabLoaded.alerts=false;loadAlertsTab();});
}

// === Scheduler Tab ===
function loadSchedulerTab() {
  fetch("/api/admin/scheduler").then(function(r){return r.json();}).then(function(res) {
    var data = res.data || [];
    if (!data.length) {
      document.getElementById("scheduler-content").innerHTML = '<div class="no-data">無排程</div>';
      return;
    }
    var html = '<table style="width:100%;"><thead><tr><th>時間</th><th>Cron 表達式</th><th>狀態</th><th>操作</th></tr></thead><tbody>';
    data.forEach(function(s, idx) {
      var isDisabled = (s.raw||"").trim().startsWith("#");
      var displayTime = s.hour + ":" + String(s.minute).padStart(2, "0");
      var statusBadge = isDisabled
        ? '<span class="badge badge-warn">已停用</span>'
        : '<span class="badge badge-ok">啟用中</span>';
      html += '<tr style="'+(isDisabled?"opacity:0.5;":"")+'">';
      html += '<td style="font-family:JetBrains Mono;font-size:16px;font-weight:500;">'+displayTime+'</td>';
      html += '<td style="font-size:12px;color:var(--c3);">'+s.raw+'</td>';
      html += '<td>'+statusBadge+'</td>';
      html += '<td style="white-space:nowrap;">';
      if (isDisabled) {
        html += '<button class="btn btn-sm btn-primary" onclick="toggleSchedule('+idx+',true)">啟用</button> ';
      } else {
        html += '<button class="btn btn-sm" style="background:var(--orange);color:white;" onclick="toggleSchedule('+idx+',false)">停用</button> ';
      }
      html += '<button class="btn btn-sm btn-danger" onclick="removeSchedule('+idx+')">刪除</button>';
      html += '</td></tr>';
    });
    html += '</tbody></table>';
    document.getElementById("scheduler-content").innerHTML = html;
  });
}

function addSchedule() {
  var hour = document.getElementById("sched-hour").value;
  var min = document.getElementById("sched-min").value;
  if (!hour) { alert("請輸入小時"); return; }
  fetch("/api/admin/scheduler").then(function(r){return r.json();}).then(function(res) {
    var times = (res.data||[]).map(function(s){return {hour:s.hour, minute:s.minute, enabled: !(s.raw||"").trim().startsWith("#")};});
    times.push({hour:hour, minute:min||"0", enabled:true});
    return fetch("/api/admin/scheduler", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({times:times})});
  }).then(function(){alert("排程已新增");_tabLoaded.scheduler=false;loadSchedulerTab();});
}

function toggleSchedule(idx, enable) {
  fetch("/api/admin/scheduler").then(function(r){return r.json();}).then(function(res) {
    var times = (res.data||[]).map(function(s, i){
      return {hour:s.hour, minute:s.minute, enabled: i===idx ? enable : !(s.raw||"").trim().startsWith("#")};
    });
    return fetch("/api/admin/scheduler", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({times:times})});
  }).then(function(){_tabLoaded.scheduler=false;loadSchedulerTab();});
}

function removeSchedule(idx) {
  if (!confirm("確定要刪除此排程？")) return;
  fetch("/api/admin/scheduler").then(function(r){return r.json();}).then(function(res) {
    var times = (res.data||[]).filter(function(s, i){return i!==idx;}).map(function(s){
      return {hour:s.hour, minute:s.minute, enabled: !(s.raw||"").trim().startsWith("#")};
    });
    return fetch("/api/admin/scheduler", {method:"PUT", headers:{"Content-Type":"application/json"}, body:JSON.stringify({times:times})});
  }).then(function(){alert("排程已刪除");_tabLoaded.scheduler=false;loadSchedulerTab();});
}

// === Reports Tab ===
function loadMonthlyReport() {
  var month = document.getElementById("report-month").value;
  if (!month) return;
  fetch("/api/admin/reports/monthly?month="+month).then(function(r){return r.json();}).then(function(res) {
    var d = res.data || {};
    var hosts = d.hosts || [];
    if (!hosts.length) {
      document.getElementById("report-content").innerHTML = '<div class="no-data">該月份無資料</div>';
      return;
    }
    var html = '<table style="width:100%;"><thead><tr><th>主機</th><th>正常</th><th>警告</th><th>異常</th><th>總計</th><th>SLA%</th></tr></thead><tbody>';
    hosts.forEach(function(h) {
      var slaColor = h.sla >= 99 ? "var(--g1)" : h.sla >= 95 ? "var(--orange)" : "var(--red)";
      html += '<tr><td><strong>'+h.hostname+'</strong></td><td>'+h.ok+'</td><td>'+h.warn+'</td><td>'+h.error+'</td><td>'+h.total+'</td><td style="font-family:JetBrains Mono;font-weight:700;color:'+slaColor+';">'+h.sla+'%</td></tr>';
    });
    html += '</tbody></table>';
    document.getElementById("report-content").innerHTML = html;
  });
}

function exportCSV() {
  var month = document.getElementById("report-month").value;
  if (!month) { alert("請先選擇月份"); return; }
  window.open("/api/admin/reports/export?format=csv&month="+month, "_blank");
}

// === Account Audit Tab ===
var _auditData = [];
function loadAuditTab() {
  fetch("/api/admin/audit/accounts").then(function(r){return r.json();}).then(function(res) {
    if (!res.success) return;
    _auditData = res.data || [];
    var th = res.thresholds || {};

    // Populate host filter
    var hostSel = document.getElementById("audit-host");
    var hosts = {};
    _auditData.forEach(function(a){ hosts[a.hostname] = 1; });
    hostSel.innerHTML = '<option value="">全部</option>' + Object.keys(hosts).map(function(h){return '<option value="'+h+'">'+h+'</option>';}).join("");

    // Populate dept filter
    var deptSel = document.getElementById("audit-dept");
    var depts = {};
    _auditData.forEach(function(a){ if(a.department) depts[a.department] = 1; });
    deptSel.innerHTML = '<option value="">全部</option>' + Object.keys(depts).map(function(d){return '<option value="'+d+'">'+d+'</option>';}).join("");

    renderAuditTable();
  });
}

function renderAuditTable() {
  var hostFilter = document.getElementById("audit-host").value;
  var deptFilter = document.getElementById("audit-dept").value;
  var riskFilter = document.getElementById("audit-risk").value;

  var filtered = _auditData.filter(function(a) {
    if (hostFilter && a.hostname !== hostFilter) return false;
    if (deptFilter && a.department !== deptFilter) return false;
    if (riskFilter === "has_risk" && a.risk_count === 0) return false;
    if (riskFilter === "pw_old" && !a.risks.some(function(r){return r.type==="pw_old";})) return false;
    if (riskFilter === "pw_expired" && !a.risks.some(function(r){return r.type==="pw_expired";})) return false;
    if (riskFilter === "no_login" && !a.risks.some(function(r){return r.type==="no_login";})) return false;
    return true;
  });

  var el = document.getElementById("audit-content");
  if (!filtered.length) {
    el.innerHTML = '<div class="no-data">無符合條件的帳號</div>';
    return;
  }

  var html = '<div style="margin-bottom:8px;font-size:13px;color:var(--c3);">共 '+filtered.length+' 個帳號</div>';
  html += '<table style="width:100%;"><thead><tr><th>主機</th><th>帳號</th><th>備註</th><th>部門</th><th>密碼變更</th><th>密碼到期</th><th>最後登入</th><th>風險</th><th>操作</th></tr></thead><tbody>';
  filtered.forEach(function(a) {
    var riskBadges = "";
    if (a.risk_count === 0) {
      riskBadges = '<span class="badge badge-ok">OK</span>';
    } else {
      riskBadges = a.risks.map(function(r) {
        return '<span class="badge badge-'+(r.level||"warn")+'" style="font-size:10px;margin:1px;">'+r.desc+'</span>';
      }).join(" ");
    }
    var noteDisplay = a.note || '<span style="color:var(--c4);">-</span>';
    var deptDisplay = a.department || '<span style="color:var(--c4);">-</span>';
    html += '<tr style="'+(a.risk_count>0?"background:#FFF8E1;":"")+'">';
    html += '<td style="font-size:12px;">'+a.hostname+'</td>';
    html += '<td><strong>'+a.user+'</strong></td>';
    html += '<td style="font-size:12px;">'+noteDisplay+'</td>';
    html += '<td style="font-size:12px;">'+deptDisplay+'</td>';
    html += '<td style="font-family:JetBrains Mono;font-size:12px;">'+a.pw_last_change+'<br><span style="color:var(--c3);">('+a.pw_age_days+'天)</span></td>';
    html += '<td style="font-family:JetBrains Mono;font-size:12px;">'+a.pw_expires+'</td>';
    html += '<td style="font-family:JetBrains Mono;font-size:12px;">'+a.last_login+'<br><span style="color:var(--c3);">('+a.login_age_days+'天)</span></td>';
    html += '<td>'+riskBadges+'</td>';
    html += '<td><button class="btn btn-sm" style="background:var(--g2);color:white;" onclick="editAccountNote(\''+a.hostname+'\',\''+a.user+'\',\''+encodeURIComponent(a.note||"")+'\',\''+encodeURIComponent(a.department||"")+'\')">編輯</button></td>';
    html += '</tr>';
  });
  html += '</tbody></table>';
  el.innerHTML = html;
}

function editAccountNote(hostname, user, noteEnc, deptEnc) {
  document.getElementById("note-hostname").value = hostname;
  document.getElementById("note-user").value = user;
  document.getElementById("note-display").value = hostname + " / " + user;
  document.getElementById("note-text").value = decodeURIComponent(noteEnc);
  document.getElementById("note-dept").value = decodeURIComponent(deptEnc);
  document.getElementById("note-modal").classList.add("active");
}

function saveAccountNote() {
  var hostname = document.getElementById("note-hostname").value;
  var user = document.getElementById("note-user").value;
  var note = document.getElementById("note-text").value;
  var dept = document.getElementById("note-dept").value;
  fetch("/api/admin/audit/accounts/"+hostname+"/"+user+"/note", {
    method: "PUT",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({note: note, department: dept})
  }).then(function(r){return r.json();}).then(function() {
    document.getElementById("note-modal").classList.remove("active");
    _tabLoaded.audit = false;
    loadAuditTab();
  });
}

// === Account Management Tab ===
function loadAcctMgmtTab() {
  // Load thresholds
  fetch("/api/admin/settings").then(function(r){return r.json();}).then(function(res) {
    var d = res.data || {};
    document.getElementById("cfg-pw-days").value = d.audit_password_days || 180;
    document.getElementById("cfg-login-days").value = d.audit_login_days || 180;
  });
  // Load HR list
  fetch("/api/admin/audit/hr").then(function(r){return r.json();}).then(function(res) {
    var data = res.data || [];
    var el = document.getElementById("hr-list");
    if (!data.length) {
      el.innerHTML = '<div class="no-data">尚無 HR 人員資料，請匯入 CSV</div>';
      return;
    }
    var html = '<table style="width:100%;"><thead><tr><th>工號</th><th>姓名</th><th>AD帳號</th><th>部門</th><th>職稱</th><th>到職日</th><th>狀態</th></tr></thead><tbody>';
    data.forEach(function(h) {
      html += '<tr><td>'+h.emp_id+'</td><td>'+h.name+'</td><td style="font-family:JetBrains Mono;">'+h.ad_account+'</td><td>'+h.department+'</td><td>'+h.title+'</td><td>'+h.hire_date+'</td><td><span class="badge badge-'+(h.status==="在職"?"ok":"warn")+'">'+h.status+'</span></td></tr>';
    });
    html += '</tbody></table>';
    el.innerHTML = html;
  });
}

function saveAuditSettings() {
  var pw = document.getElementById("cfg-pw-days").value;
  var login = document.getElementById("cfg-login-days").value;
  fetch("/api/admin/audit/settings", {
    method: "PUT",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({pw_days: pw, login_days: login})
  }).then(function(r){return r.json();}).then(function(res) {
    alert("閾值已儲存：密碼 "+pw+" 天 / 登入 "+login+" 天");
  });
}

function uploadHR(input) {
  if (!input.files.length) return;
  var formData = new FormData();
  formData.append("file", input.files[0]);
  fetch("/api/admin/audit/hr/import", {method:"POST", body:formData})
    .then(function(r){return r.json();}).then(function(res) {
      alert(res.message || "匯入完成");
      input.value = "";
      _tabLoaded.acctmgmt = false;
      loadAcctMgmtTab();
    });
}

// === Worklog Tab ===
function loadWorklogTab() {
  fetch("/api/admin/worklog").then(function(r){return r.json();}).then(function(res) {
    var data = res.data || [];
    if (!data.length) {
      document.getElementById("worklog-content").innerHTML = '<div class="no-data">無操作紀錄</div>';
      return;
    }
    var html = '<table style="width:100%;"><thead><tr><th>時間</th><th>使用者</th><th>動作</th><th>詳情</th><th>IP</th></tr></thead><tbody>';
    data.forEach(function(w) {
      html += '<tr><td style="white-space:nowrap;font-family:JetBrains Mono;font-size:12px;">'+w.timestamp.replace("T"," ").substring(0,19)+'</td><td>'+w.user+'</td><td><span class="badge badge-ok" style="font-size:11px;">'+w.action+'</span></td><td style="font-size:12px;">'+w.detail+'</td><td style="font-size:12px;color:var(--c3);">'+w.ip+'</td></tr>';
    });
    html += '</tbody></table>';
    document.getElementById("worklog-content").innerHTML = html;
  });
}


// ===== nmon Schedule (v3.9.4.0: per-host interval) =====
var _nmonHosts = [];
var _nmonDefaultInterval = 5;
var _INTERVAL_LABELS = {1:"每 1 分鐘", 5:"每 5 分鐘", 15:"每 15 分鐘", 30:"每 30 分鐘", 60:"每 1 小時", 1440:"每 24 小時"};

function loadNmonSchedule() {
  var container = document.getElementById("nmon-sched-hosts");
  if (!container) return;
  container.innerHTML = '載入中...';
  fetch("/api/nmon/schedule").then(function(r){return r.json();}).then(function(res){
    if (!res.success) { container.innerHTML = '<div style="color:var(--red);">載入失敗: '+(res.error||'?')+'</div>'; return; }
    _nmonHosts = res.data.hosts || [];
    _nmonDefaultInterval = res.data.current_interval_min || 5;
    document.getElementById("nmon-sched-interval").value = String(_nmonDefaultInterval);
    renderNmonHosts();
  });
}

function _intervalOptionsHTML(selected) {
  var opts = [1,5,15,30,60,1440];
  return opts.map(function(v){
    return '<option value="'+v+'"'+(v==selected?' selected':'')+'>'+_INTERVAL_LABELS[v]+'</option>';
  }).join('');
}

function renderNmonHosts() {
  var q = (document.getElementById("nmon-sched-search").value||"").toLowerCase();
  var showAll = document.getElementById("nmon-sched-show-all").checked;
  var container = document.getElementById("nmon-sched-hosts");
  var visible = _nmonHosts.filter(function(h){
    if (!showAll && !h.nmon_supported) return false;
    if (!q) return true;
    return (h.hostname||"").toLowerCase().indexOf(q)>=0 ||
           (h.ip||"").toLowerCase().indexOf(q)>=0 ||
           (h.os||"").toLowerCase().indexOf(q)>=0;
  });
  if (visible.length === 0) {
    container.innerHTML = '<div style="color:var(--c3);padding:12px;">無符合主機</div>';
    document.getElementById("nmon-sched-count").textContent = "(0 台)";
    return;
  }
  var enabledCount = _nmonHosts.filter(function(h){return h.nmon_enabled;}).length;
  document.getElementById("nmon-sched-count").textContent = "(顯示 "+visible.length+" / 共 "+_nmonHosts.length+" 台，已啟用 "+enabledCount+" 台)";

  var html = '';
  visible.forEach(function(h){
    var disabled = !h.nmon_supported;
    var hostInterval = h.nmon_interval_min || _nmonDefaultInterval;
    var tierBadge = h.tier ? '<span style="font-size:10px;margin-left:4px;color:var(--c4);">['+h.tier+']</span>' : '';
    var deployInfo = '';
    if (h.nmon_enabled && h.nmon_deployed_at) {
      deployInfo = '<div style="font-size:10px;color:var(--g1);margin-top:4px;">✓ '+h.nmon_deployed_at.substring(5,16)+'</div>';
    } else if (!h.nmon_supported) {
      deployInfo = '<div style="font-size:10px;color:var(--red);margin-top:4px;">不支援 ('+(h.os_group||'?')+')</div>';
    }
    html += '<div class="nmon-card" data-host="'+h.hostname+'" style="display:inline-flex;flex-direction:column;align-items:flex-start;border:1px solid #ddd;border-radius:6px;padding:8px 12px;background:#fff;opacity:'+(disabled?'0.45':'1')+';min-width:240px;">';
    html += '<label style="display:flex;align-items:center;gap:6px;font-size:13px;cursor:'+(disabled?'not-allowed':'pointer')+';">';
    html += '<input type="checkbox" class="nmon-host-cb" value="'+h.hostname+'" '+(h.nmon_enabled?'checked':'')+' '+(disabled?'disabled':'')+' onchange="updateNmonCount()">';
    html += '<strong>'+h.hostname+'</strong>';
    html += tierBadge;
    html += '</label>';
    html += '<div style="font-size:11px;color:var(--c3);margin-top:2px;">'+(h.ip||'-')+' · '+(h.os||'-')+(h.system_name?' · '+h.system_name:'')+'</div>';
    // per-host interval dropdown
    if (!disabled) {
      html += '<div style="margin-top:6px;font-size:11px;color:var(--c3);display:flex;align-items:center;gap:4px;">頻率 <select class="nmon-host-iv" data-host="'+h.hostname+'" style="font-size:11px;padding:2px 4px;">';
      html += _intervalOptionsHTML(hostInterval);
      html += '</select></div>';
    }
    html += deployInfo;
    html += '</div>';
  });
  container.innerHTML = html;
  updateNmonCount();
}

function toggleAllNmon() {
  var checked = document.getElementById("nmon-sched-all").checked;
  document.querySelectorAll(".nmon-host-cb:not([disabled])").forEach(function(cb){ cb.checked = checked; });
  updateNmonCount();
}

function updateNmonCount() {
  var n = document.querySelectorAll(".nmon-host-cb:checked").length;
  var total = document.querySelectorAll(".nmon-host-cb:not([disabled])").length;
  document.getElementById("nmon-sched-all").checked = (n > 0 && n === total);
}

// 批次套用: 把頂部頻率下拉套到所有「勾選中」的 host 下拉
function applyBatchInterval() {
  var iv = document.getElementById("nmon-sched-interval").value;
  var checked = document.querySelectorAll(".nmon-host-cb:checked");
  var applied = 0;
  checked.forEach(function(cb){
    var hn = cb.value;
    var sel = document.querySelector('.nmon-host-iv[data-host="'+hn+'"]');
    if (sel) { sel.value = iv; applied++; }
  });
  var statusEl = document.getElementById("nmon-sched-status");
  statusEl.innerHTML = '<span style="color:var(--g1);">批次設 '+applied+' 台為 '+_INTERVAL_LABELS[iv]+'（記得按「套用」生效）</span>';
}

function _collectHostConfigs() {
  var cfgs = [];
  document.querySelectorAll(".nmon-host-cb:checked").forEach(function(cb){
    var hn = cb.value;
    var sel = document.querySelector('.nmon-host-iv[data-host="'+hn+'"]');
    var iv = sel ? parseInt(sel.value,10) : _nmonDefaultInterval;
    cfgs.push({hostname: hn, interval_min: iv});
  });
  return cfgs;
}

function saveNmonSchedule() {
  var configs = _collectHostConfigs();
  // preview
  fetch("/api/nmon/schedule/preview", {
    method:"POST", headers:{"Content-Type":"application/json"},
    body: JSON.stringify({host_configs: configs}),
  }).then(function(r){return r.json();}).then(function(res){
    if (!res.success) { alert("預覽失敗: "+(res.error||"?")); return; }
    var d = res.data;
    // 組 Modal
    var msg = '套用 nmon 排程\n\n';
    if (d.groups && d.groups.length) {
      msg += '▶ 將啟用 (依頻率分組):\n';
      d.groups.forEach(function(g){
        msg += '  ['+_INTERVAL_LABELS[g.interval_min]+'] '+g.count+' 台: '+g.hosts.slice(0,5).join(', ');
        if (g.hosts.length > 5) msg += ' ... +'+(g.hosts.length-5);
        msg += '\n';
      });
    } else {
      msg += '▶ 無啟用主機\n';
    }
    if (d.to_disable && d.to_disable.length) {
      msg += '\n▶ 將停用 ('+d.to_disable.length+' 台, 僅清 cron, 歷史資料保留):\n';
      msg += '  '+d.to_disable.slice(0,10).join(', ');
      if (d.to_disable.length > 10) msg += ' ... +'+(d.to_disable.length-10);
      msg += '\n';
    }
    if (d.skipped_windows && d.skipped_windows.length) {
      msg += '\n⚠ 忽略 Windows: '+d.skipped_windows.join(', ');
    }
    msg += '\n\n確定套用？';
    if (!confirm(msg)) return;

    // apply
    var btn = document.getElementById("nmon-sched-apply-btn") || document.querySelector("button[onclick='saveNmonSchedule()']");
    var origText = btn ? btn.textContent : '套用';
    if (btn) { btn.disabled = true; btn.textContent = '⏳ 部署中...'; }
    var statusEl = document.getElementById("nmon-sched-status");
    statusEl.textContent = '背景部署中...';

    fetch("/api/nmon/schedule", {
      method:"POST", headers:{"Content-Type":"application/json"},
      body: JSON.stringify({host_configs: configs, confirm: true}),
    }).then(function(r){return r.json();}).then(function(res2){
      if (!res2.success) {
        statusEl.innerHTML = '<span style="color:var(--red);">失敗: '+(res2.error||'?')+'</span>';
        alert('套用失敗: '+(res2.error||'?'));
      } else {
        statusEl.innerHTML = '<span style="color:var(--g1);">✓ '+res2.data.message+'</span>';
        setTimeout(loadNmonSchedule, 30000);
      }
    }).catch(function(e){
      statusEl.innerHTML = '<span style="color:var(--red);">網路錯誤: '+e+'</span>';
    }).finally(function(){
      if (btn) { btn.disabled = false; btn.textContent = origText; }
    });
  });
}
// ===== nmon Schedule end =====
// ===== Feature Flag UI Filter (v3.10.1.0) =====
// 根據 window.FEATURES 隱藏 data-feature 標記的 tab 按鈕/panel,
// 且如果整個 admin-nav-group 底下所有 tab 都被藏, 整組也藏
(function(){
  function applyFeatureFilter() {
    var FEATURES = window.FEATURES || {};
    // 隱藏 data-feature 對應 false 的元素
    document.querySelectorAll("[data-feature]").forEach(function(el){
      var key = el.getAttribute("data-feature");
      if (FEATURES[key] === false) {
        el.style.display = "none";
        el.setAttribute("data-hidden-by-feature", "1");
      }
    });
    // 收摺 admin-nav-group: 子項全被藏就隱藏整組
    document.querySelectorAll(".admin-nav-group").forEach(function(g){
      var tabs = g.querySelectorAll(".admin-tab");
      if (tabs.length === 0) return;
      var visible = Array.from(tabs).filter(function(t){ return t.style.display !== "none"; });
      if (visible.length === 0) {
        g.style.display = "none";
      }
    });
    // 如果當前 active tab 剛好被藏, 自動切第一個還看得到的 tab
    var active = document.querySelector(".admin-tab.active");
    if (active && active.style.display === "none") {
      var firstVisible = document.querySelector(".admin-tab:not([style*='display: none'])");
      if (firstVisible) firstVisible.click();
    }
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", applyFeatureFilter);
  } else {
    applyFeatureFilter();
  }
})();
// ===== end =====


// ===== 系統聯通圖管理 (v3.14.0.0+) =====
var _depSysCache = [];
var _depEditingSysId = null;
var _depEditingRelId = null;

function loadDependenciesMgmtTab() {
  loadDependenciesMgmtSystems();
  loadDependenciesMgmtRelations();
  loadDependenciesMgmtSchedule();
}

function loadDependenciesMgmtSchedule() {
  fetch("/api/dependencies/collect/schedule", {credentials:"include"}).then(r => r.json()).then(res => {
    if (!res.success) return;
    const d = res.data || {};
    const sel = document.getElementById("depmgmt-sched-interval");
    const cb = document.getElementById("depmgmt-sched-bizhour");
    const st = document.getElementById("depmgmt-sched-status");
    if (sel) sel.value = String(d.interval_min || 0);
    if (cb) cb.checked = !!d.business_hours_only;
    if (st) {
      if (d.enabled) {
        const last = d.last_run_at ? new Date(d.last_run_at).toLocaleString('zh-TW',{hour12:false}).slice(5) : "—";
        st.innerHTML = '<span style="color:var(--g1);">✓ 已啟用</span> <span style="color:var(--c3);">最後跑: ' + last + '</span>';
      } else {
        st.innerHTML = '<span style="color:var(--c4);">未啟用</span>';
      }
    }
  });
}

async function depMgmtCollectNow() {
  const btn = document.getElementById("depmgmt-collect-btn");
  const st = document.getElementById("depmgmt-collect-status");
  btn.disabled = true;
  const orig = btn.innerHTML;
  btn.innerHTML = "⏳ 採集中...";
  st.textContent = "ansible-playbook 執行中,5 秒輪詢進度...";
  try {
    const r = await fetch("/api/dependencies/collect/trigger", {method:"POST", credentials:"include"});
    const res = await r.json();
    if (!res.success) {
      st.innerHTML = '<span style="color:var(--red);">✗ ' + (res.error || "失敗") + '</span>';
      btn.disabled = false; btn.innerHTML = orig;
      return;
    }
    const runId = res.data.run_id;
    let polls = 0;
    const timer = setInterval(async function() {
      polls++;
      try {
        const s = await fetch("/api/dependencies/collect/status/" + runId, {credentials:"include"}).then(x => x.json());
        if (s.success && s.data && (s.data.status === "success" || s.data.status === "failed")) {
          clearInterval(timer);
          btn.disabled = false; btn.innerHTML = orig;
          if (s.data.status === "success") {
            const m = s.data;
            st.innerHTML = '<span style="color:var(--g1);">✓ 完成</span> 新增 ' + (m.edges_added||0) + ' / 更新 ' + (m.edges_updated||0) + (m.new_unknowns && m.new_unknowns.length ? ' / 新發現 ' + m.new_unknowns.length + ' 個未知 IP' : '');
            if (typeof _dashToast === "function") _dashToast("✓ 採集完成", "success");
          } else {
            st.innerHTML = '<span style="color:var(--red);">✗ 採集失敗</span>';
            if (typeof _dashToast === "function") _dashToast("✗ 採集失敗", "error");
          }
        } else if (polls > 60) {
          clearInterval(timer);
          btn.disabled = false; btn.innerHTML = orig;
          st.innerHTML = '<span style="color:var(--orange);">⚠ 5 分鐘未完成,請看 logs/dep_collect_*.log</span>';
        }
      } catch(e) {}
    }, 5000);
  } catch(e) {
    st.innerHTML = '<span style="color:var(--red);">✗ ' + e.message + '</span>';
    btn.disabled = false; btn.innerHTML = orig;
  }
}

async function depMgmtSaveSchedule() {
  const interval = parseInt(document.getElementById("depmgmt-sched-interval").value, 10);
  const biz = document.getElementById("depmgmt-sched-bizhour").checked;
  const st = document.getElementById("depmgmt-sched-status");
  st.textContent = "套用中...";
  try {
    const r = await fetch("/api/dependencies/collect/schedule", {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      credentials: "include",
      body: JSON.stringify({interval_min: interval, business_hours_only: biz}),
    });
    const res = await r.json();
    if (!res.success) {
      st.innerHTML = '<span style="color:var(--red);">✗ ' + (res.error || "失敗") + '</span>';
      return;
    }
    if (typeof _dashToast === "function") _dashToast("✓ " + (res.data.message || "已套用"), "success");
    loadDependenciesMgmtSchedule();
  } catch(e) {
    st.innerHTML = '<span style="color:var(--red);">✗ ' + e.message + '</span>';
  }
}

function loadDependenciesMgmtSystems() {
  var box = document.getElementById("depmgmt-sys-table");
  if (!box) return;
  fetch("/api/dependencies/systems", {credentials:"include"}).then(function(r){return r.json();}).then(function(res){
    if (!res.success) { box.innerHTML = '<span style="color:var(--red);">載入失敗: '+(res.error||"")+'</span>'; return; }
    _depSysCache = res.data || [];
    document.getElementById("depmgmt-sys-count").textContent = "(共 " + _depSysCache.length + " 個)";
    if (!_depSysCache.length) { box.innerHTML = '<div style="padding:24px;text-align:center;color:var(--c3);">尚無資料,點「➕ 新增系統」建立第一個業務系統</div>'; return; }
    var html = '<table class="data-table" style="width:100%;font-size:13px;"><thead><tr>'+
      '<th>ID</th><th>名稱</th><th>級別</th><th>類別</th><th>負責人</th><th>主機</th><th>說明</th><th style="width:120px;">操作</th>'+
      '</tr></thead><tbody>';
    _depSysCache.forEach(function(s){
      var t = (s.tier||"C").toUpperCase();
      html += '<tr>'+
        '<td><code>'+escDep(s.system_id)+'</code></td>'+
        '<td>'+escDep(s.display_name||s.system_id)+'</td>'+
        '<td><span class="dep-tier-badge dep-tier-'+t+'">'+t+'</span></td>'+
        '<td>'+escDep(s.category||"")+'</td>'+
        '<td>'+escDep(s.owner||"-")+'</td>'+
        '<td style="font-size:11px;color:var(--c3);">'+escDep((s.host_refs||[]).join(", ")||"-")+'</td>'+
        '<td style="font-size:11px;color:var(--c3);max-width:240px;">'+escDep(s.description||"")+'</td>'+
        '<td><button class="btn btn-sm" onclick="editDependencySystem(\''+escDep(s.system_id)+'\')">編輯</button> <button class="btn btn-sm" style="background:var(--red);color:#fff;" onclick="deleteDependencySystem(\''+escDep(s.system_id)+'\')">刪除</button></td>'+
        '</tr>';
    });
    html += '</tbody></table>';
    box.innerHTML = html;
  });
}

function loadDependenciesMgmtRelations() {
  var box = document.getElementById("depmgmt-rel-table");
  if (!box) return;
  var src = document.getElementById("depmgmt-rel-source").value;
  var url = "/api/dependencies/relations" + (src ? "?source="+encodeURIComponent(src) : "");
  fetch(url, {credentials:"include"}).then(function(r){return r.json();}).then(function(res){
    if (!res.success) { box.innerHTML = '<span style="color:var(--red);">載入失敗</span>'; return; }
    var rels = res.data || [];
    document.getElementById("depmgmt-rel-count").textContent = "(共 " + rels.length + " 條)";
    if (!rels.length) { box.innerHTML = '<div style="padding:24px;text-align:center;color:var(--c3);">尚無關係,點「➕ 新增關係」建立第一條依賴邊</div>'; return; }
    var html = '<table class="data-table" style="width:100%;font-size:13px;"><thead><tr>'+
      '<th>來源 →</th><th>→ 目標</th><th>類型</th><th>協定/Port</th><th>來源</th><th>確認</th><th>說明</th><th style="width:120px;">操作</th>'+
      '</tr></thead><tbody>';
    rels.forEach(function(e){
      var srcLabel = e.source==="ss-tunp" ? '<span style="color:var(--orange);">自動</span>' : (e.source==="inferred" ? '推斷' : '手動');
      var confirmed = e.manual_confirmed ? '<span style="color:var(--g1);">✓</span>' : '<span style="color:var(--orange);">待確認</span>';
      html += '<tr>'+
        '<td><code>'+escDep(e.from_system)+'</code></td>'+
        '<td><code>'+escDep(e.to_system)+'</code></td>'+
        '<td>'+escDep(e.relation_type||"unknown")+'</td>'+
        '<td>'+escDep(e.protocol||"TCP")+':'+escDep(e.port||"-")+'</td>'+
        '<td>'+srcLabel+'</td>'+
        '<td>'+confirmed+'</td>'+
        '<td style="font-size:11px;color:var(--c3);max-width:240px;">'+escDep(e.description||"")+'</td>'+
        '<td>'+
          (e.manual_confirmed ? '' : '<button class="btn btn-sm btn-primary" onclick="confirmDepRelation(\''+escDep(e._id)+'\')">確認</button> ') +
          '<button class="btn btn-sm" style="background:var(--red);color:#fff;" onclick="deleteDependencyRelation(\''+escDep(e._id)+'\')">刪除</button></td>'+
        '</tr>';
    });
    html += '</tbody></table>';
    box.innerHTML = html;
  });
}

function escDep(s) {
  return String(s==null?"":s).replace(/[&<>"']/g, function(c){return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c];});
}

function openDepSystemModal() {
  _depEditingSysId = null;
  document.getElementById("dep-sys-modal-title").textContent = "新增業務系統";
  document.getElementById("dep-sys-id").value = "";
  document.getElementById("dep-sys-id").disabled = false;
  document.getElementById("dep-sys-name").value = "";
  document.getElementById("dep-sys-tier").value = "C";
  document.getElementById("dep-sys-category").value = "AP";
  document.getElementById("dep-sys-owner").value = "";
  document.getElementById("dep-sys-hosts").value = "";
  document.getElementById("dep-sys-desc").value = "";
  document.getElementById("dep-sys-modal").classList.add("active");
}

function editDependencySystem(systemId) {
  var s = _depSysCache.find(function(x){return x.system_id===systemId;});
  if (!s) return;
  _depEditingSysId = systemId;
  document.getElementById("dep-sys-modal-title").textContent = "編輯系統: " + systemId;
  document.getElementById("dep-sys-id").value = s.system_id;
  document.getElementById("dep-sys-id").disabled = true;
  document.getElementById("dep-sys-name").value = s.display_name||"";
  document.getElementById("dep-sys-tier").value = (s.tier||"C").toUpperCase();
  document.getElementById("dep-sys-category").value = s.category||"AP";
  document.getElementById("dep-sys-owner").value = s.owner||"";
  document.getElementById("dep-sys-hosts").value = (s.host_refs||[]).join(", ");
  document.getElementById("dep-sys-desc").value = s.description||"";
  document.getElementById("dep-sys-modal").classList.add("active");
}

async function saveDependencySystem() {
  var sysId = document.getElementById("dep-sys-id").value.trim();
  if (!sysId) { _dashToast && _dashToast("✗ system_id 必填", "error"); return; }
  var hosts = document.getElementById("dep-sys-hosts").value.split(",").map(function(x){return x.trim();}).filter(Boolean);
  var payload = {
    system_id: sysId,
    display_name: document.getElementById("dep-sys-name").value.trim(),
    tier: document.getElementById("dep-sys-tier").value,
    category: document.getElementById("dep-sys-category").value,
    owner: document.getElementById("dep-sys-owner").value.trim(),
    host_refs: hosts,
    description: document.getElementById("dep-sys-desc").value.trim(),
  };
  var url = _depEditingSysId ? "/api/dependencies/systems/"+encodeURIComponent(_depEditingSysId) : "/api/dependencies/systems";
  var method = _depEditingSysId ? "PUT" : "POST";
  try {
    var r = await fetch(url, {method:method, headers:{"Content-Type":"application/json"}, credentials:"include", body:JSON.stringify(payload)});
    var res = await r.json();
    if (!res.success) { _dashToast && _dashToast("✗ "+(res.error||"儲存失敗"), "error"); return; }
    _dashToast && _dashToast("✓ 已儲存", "success");
    document.getElementById("dep-sys-modal").classList.remove("active");
    loadDependenciesMgmtSystems();
  } catch(e) { _dashToast && _dashToast("✗ "+e.message, "error"); }
}

async function deleteDependencySystem(systemId) {
  if (!confirm("確定刪除系統「"+systemId+"」?\n注意:相關的依賴邊也會一併刪除")) return;
  try {
    var r = await fetch("/api/dependencies/systems/"+encodeURIComponent(systemId), {method:"DELETE", credentials:"include"});
    var res = await r.json();
    if (!res.success) { _dashToast && _dashToast("✗ "+(res.error||""), "error"); return; }
    _dashToast && _dashToast("✓ 已刪除 (連帶 "+res.data.cascade_relations+" 條邊)", "success");
    loadDependenciesMgmtTab();
  } catch(e) { _dashToast && _dashToast("✗ "+e.message, "error"); }
}

function openDepRelationModal() {
  _depEditingRelId = null;
  document.getElementById("dep-rel-modal-title").textContent = "新增依賴關係";
  var fromSel = document.getElementById("dep-rel-from");
  var toSel = document.getElementById("dep-rel-to");
  var opts = '<option value="">--</option>' + _depSysCache.map(function(s){
    return '<option value="'+escDep(s.system_id)+'">'+escDep(s.system_id)+' ('+escDep(s.display_name||"")+')</option>';
  }).join("");
  fromSel.innerHTML = opts;
  toSel.innerHTML = opts;
  document.getElementById("dep-rel-type").value = "unknown";
  document.getElementById("dep-rel-proto").value = "TCP";
  document.getElementById("dep-rel-port").value = "";
  document.getElementById("dep-rel-desc").value = "";
  document.getElementById("dep-rel-modal").classList.add("active");
}

async function saveDependencyRelation() {
  var fs = document.getElementById("dep-rel-from").value;
  var ts = document.getElementById("dep-rel-to").value;
  if (!fs || !ts) { _dashToast && _dashToast("✗ 來源/目標必選", "error"); return; }
  if (fs === ts) { _dashToast && _dashToast("✗ 不能連自己", "error"); return; }
  var payload = {
    from_system: fs,
    to_system: ts,
    relation_type: document.getElementById("dep-rel-type").value,
    protocol: document.getElementById("dep-rel-proto").value,
    port: parseInt(document.getElementById("dep-rel-port").value || "0", 10),
    description: document.getElementById("dep-rel-desc").value.trim(),
    source: "manual",
    manual_confirmed: true,
  };
  try {
    var r = await fetch("/api/dependencies/relations", {method:"POST", headers:{"Content-Type":"application/json"}, credentials:"include", body:JSON.stringify(payload)});
    var res = await r.json();
    if (!res.success) { _dashToast && _dashToast("✗ "+(res.error||""), "error"); return; }
    _dashToast && _dashToast("✓ 已新增", "success");
    document.getElementById("dep-rel-modal").classList.remove("active");
    loadDependenciesMgmtRelations();
  } catch(e) { _dashToast && _dashToast("✗ "+e.message, "error"); }
}

async function confirmDepRelation(relId) {
  try {
    var r = await fetch("/api/dependencies/relations/"+encodeURIComponent(relId), {method:"PUT", headers:{"Content-Type":"application/json"}, credentials:"include", body:JSON.stringify({manual_confirmed: true})});
    var res = await r.json();
    if (!res.success) { _dashToast && _dashToast("✗ "+(res.error||""), "error"); return; }
    _dashToast && _dashToast("✓ 已確認", "success");
    loadDependenciesMgmtRelations();
  } catch(e) { _dashToast && _dashToast("✗ "+e.message, "error"); }
}

async function deleteDependencyRelation(relId) {
  if (!confirm("確定刪除這條依賴關係?")) return;
  try {
    var r = await fetch("/api/dependencies/relations/"+encodeURIComponent(relId), {method:"DELETE", credentials:"include"});
    var res = await r.json();
    if (!res.success) { _dashToast && _dashToast("✗ "+(res.error||""), "error"); return; }
    _dashToast && _dashToast("✓ 已刪除", "success");
    loadDependenciesMgmtRelations();
  } catch(e) { _dashToast && _dashToast("✗ "+e.message, "error"); }
}
// ===== END 系統聯通圖管理 =====
