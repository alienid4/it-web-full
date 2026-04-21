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
    "reports": function(){},
    "audit": loadAuditTab,
    "acctmgmt": loadAcctMgmtTab,
    "worklog": loadWorklogTab,
    "security-audit": loadSecurityAuditTab,
    "linux-init": loadLinuxInitTab,
  };
  if (loaders[tab]) loaders[tab]();
}

function doLogout() {
  fetch("/api/admin/logout", {method:"POST"}).then(function(){ location.href = "/login"; });
}

function adminAction(url, method, confirmMsg) {
  if (confirmMsg && !confirm(confirmMsg)) return;
  fetch(url, {method: method, headers:{"Content-Type":"application/json"}, body: JSON.stringify({})})
    .then(function(r){return r.json();})
    .then(function(res){ alert(res.message || res.output || JSON.stringify(res)); _tabLoaded = {}; });
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
    document.getElementById("h-hostname").value = h.hostname || "";
    document.getElementById("h-hostname").readOnly = true;
    document.getElementById("h-ip").value = h.ip || "";
    document.getElementById("h-os").value = h.os || "";
    document.getElementById("h-osgroup").value = h.os_group || "";
    document.getElementById("h-env").value = h.environment || "";
    document.getElementById("h-custodian").value = h.custodian || "";
    document.getElementById("h-dept").value = h.department || "";
    document.getElementById("h-group").value = h.group || "";
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
  var data = {
    hostname: hn,
    ip: document.getElementById("h-ip").value,
    os: document.getElementById("h-os").value,
    os_group: document.getElementById("h-osgroup").value,
    environment: document.getElementById("h-env").value,
    custodian: document.getElementById("h-custodian").value,
    department: document.getElementById("h-dept").value,
    group: document.getElementById("h-group").value,
    status: "使用中",
    has_python: true,
  };
  var url = isEdit ? "/api/admin/hosts/" + hn : "/api/admin/hosts";
  var method = isEdit ? "PUT" : "POST";
  fetch(url, {method:method, headers:{"Content-Type":"application/json"}, body:JSON.stringify(data)})
    .then(function(r){return r.json();}).then(function(res) {
      alert(res.message || "已儲存");
      closeHostModal();
      _tabLoaded.hosts = false;
      loadHostsTab();
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
