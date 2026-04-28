#!/usr/bin/env python3
"""
v3.15.5.0 hosts collection 29 欄資產表對齊
- 加 5 個缺欄位: device_model / rack_no / quantity / hardware_seq / sys_admin
- 補 secansible / WIN-7L4JNM4P2KN 缺的資產資料 (best-guess, 你可事後在 UI 改)
- 跑完印 before/after 對照給人看

執行: 透過 install.sh 呼叫 (會 cd 進 webapp 並走 podman exec mongosh)
"""
import sys
import os

# 走 podman exec 直接下 mongo 指令 (不依賴 webapp Python 環境)
DB_NAME = "inspection"

JS_SCRIPT = r"""
const NEW_FIELDS = ["device_model", "rack_no", "quantity", "hardware_seq", "sys_admin"];

print("=== before ===");
db.hosts.find({}, {hostname:1, asset_seq:1, group_name:1, tier:1, ap_owner:1, system_name:1, _id:0}).forEach(d => printjson(d));

// (1) 全主機補 5 新欄位 (預設空字串, quantity=1)
const ts = new Date().toISOString();
NEW_FIELDS.forEach(f => {
  const def = (f === "quantity") ? 1 : "";
  const r = db.hosts.updateMany({ [f]: { $exists: false } }, { $set: { [f]: def } });
  print("[+] 加欄位 " + f + ": " + r.modifiedCount + " 台主機補上 default=" + JSON.stringify(def));
});

// (1.5) 補空的 tier / ap_owner / system_name (per-host)
const PER_HOST_FILL = {
  "secansible":       { tier: "金", ap_owner: "Alienlee", system_name: "巡檢系統" },
  "secclient1":       { tier: "銅", ap_owner: "Alienlee", system_name: "巡檢測試環境" },
  "sec9c2":           { tier: "銅", ap_owner: "Alienlee", system_name: "巡檢測試環境" },
  "WIN-7L4JNM4P2KN":  { tier: "銅", ap_owner: "Alienlee", system_name: "巡檢測試環境" },
};
Object.keys(PER_HOST_FILL).forEach(hn => {
  const h = db.hosts.findOne({hostname: hn});
  if (!h) return;
  const setObj = {};
  Object.keys(PER_HOST_FILL[hn]).forEach(k => {
    if (!h[k] || h[k] === "" || h[k] === null) setObj[k] = PER_HOST_FILL[hn][k];
  });
  if (Object.keys(setObj).length > 0) {
    db.hosts.updateOne({hostname: hn}, {$set: setObj});
    print("[+] " + hn + " 補 " + Object.keys(setObj).length + " 巡檢欄位: " + Object.keys(setObj).join(","));
  }
});

// (2) 補 secansible 缺資料 (best-guess)
const secansibleSet = {
  division: "資訊管理處",
  department: "資訊架構部",
  asset_seq: "HW-00001003",
  group_name: "H9-IT 管理性系統設備",
  apid: "巡檢系統",
  asset_name: "L-003",
  device_type: "地端資產 (VM)",
  device_model: "VMware VM",
  asset_usage: "AP Server / DB Server",
  location: "LAB機房",
  quantity: 1,
  owner: "資訊架構部",
  bigip: "無",
  user: "lab-admin",
  user_unit: "資訊架構部",
  note: "巡檢系統主機 (Flask + MongoDB + Cloudflared)",
  company: "敦南總公司",
  confidentiality: 1,
  integrity: 1,
  availability: 1,
  request_no: "E000000000003",
  infra: "LAB測試環境",
  updated_at: ts,
};
// 用 $set 但不覆蓋已有非空值
const sec = db.hosts.findOne({hostname: "secansible"});
if (sec) {
  const setObj = {};
  Object.keys(secansibleSet).forEach(k => {
    if (!sec[k] || sec[k] === "" || sec[k] === null) setObj[k] = secansibleSet[k];
  });
  if (Object.keys(setObj).length > 0) {
    db.hosts.updateOne({hostname: "secansible"}, {$set: setObj});
    print("[+] secansible 補 " + Object.keys(setObj).length + " 欄: " + Object.keys(setObj).join(","));
  } else {
    print("[=] secansible 已完整, 不動");
  }
}

// (3) 補 WIN-7L4JNM4P2KN 缺資料
const winSet = {
  division: "資訊管理處",
  department: "資訊架構部",
  asset_seq: "HW-00001004",
  group_name: "H4-測試設備",
  apid: "巡檢測試環境",
  asset_name: "W-001",
  device_type: "地端資產 (VM)",
  device_model: "VMware VM",
  asset_usage: "Windows 測試",
  location: "LAB機房",
  quantity: 1,
  owner: "資訊架構部",
  bigip: "無",
  user: "lab-admin",
  user_unit: "資訊架構部",
  note: "Windows Server 2019 測試主機",
  company: "敦南總公司",
  confidentiality: 1,
  integrity: 0,
  availability: 1,
  request_no: "E000000000004",
  infra: "LAB測試環境",
  updated_at: ts,
};
const win = db.hosts.findOne({hostname: "WIN-7L4JNM4P2KN"});
if (win) {
  const setObj = {};
  Object.keys(winSet).forEach(k => {
    if (!win[k] || win[k] === "" || win[k] === null) setObj[k] = winSet[k];
  });
  if (Object.keys(setObj).length > 0) {
    db.hosts.updateOne({hostname: "WIN-7L4JNM4P2KN"}, {$set: setObj});
    print("[+] WIN-7L4JNM4P2KN 補 " + Object.keys(setObj).length + " 欄: " + Object.keys(setObj).join(","));
  } else {
    print("[=] WIN-7L4JNM4P2KN 已完整, 不動");
  }
}

print("");
print("=== after ===");
db.hosts.find({}, {hostname:1, asset_seq:1, group_name:1, device_model:1, _id:0}).forEach(d => printjson(d));
"""

# 透過 podman exec 跑 mongosh
import subprocess
proc = subprocess.run(
    ["podman", "exec", "-i", "mongodb", "mongosh", DB_NAME, "--quiet"],
    input=JS_SCRIPT, text=True, capture_output=True, timeout=60,
)
print(proc.stdout)
if proc.returncode != 0:
    print("STDERR:", proc.stderr, file=sys.stderr)
    sys.exit(proc.returncode)
