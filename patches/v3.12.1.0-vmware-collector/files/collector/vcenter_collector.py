#!/usr/bin/env python3
"""
VMware vCenter Collector v3.12.1.0
每 8 小時跑一次 (cron) 或手動觸發, 抓 Cluster/Host/CPU/Mem/版本 快照寫 MongoDB。

嚴格 read-only:
  - 只呼叫 RetrieveContent / CreateContainerView / 讀屬性
  - ContainerView 用完一律 Destroy
  - 絕不呼叫 Create*/Modify*/Destroy VM/Reconfigure*/PowerOn*/PowerOff*
  - 開發期用 administrator 帳號, 更要自律 (見 memory: feedback_vmware_admin_readonly.md)

Usage:
  python3 vcenter_collector.py                 # 跑全部 VC (vcenters.yaml)
  python3 vcenter_collector.py --only 板橋     # 只跑指定 label 的 VC
  python3 vcenter_collector.py --dry-run       # 連線抓資料但不寫 MongoDB (debug)
  python3 vcenter_collector.py --verbose       # 多印 log
  python3 vcenter_collector.py --mock-write    # 不連 VC, 寫 mock snapshots 到 MongoDB (家裡 221 測 pipeline)
"""
from __future__ import annotations

import os
import ssl
import sys
import json
import logging
import argparse
import subprocess
from datetime import datetime
from pathlib import Path

import yaml
from pyVim.connect import SmartConnect, Disconnect
from pyVmomi import vim
from pymongo import MongoClient, ASCENDING, DESCENDING

# ============================================================
#  路徑偵測 (221 / 13 兩邊通)
# ============================================================
def detect_inspection_home() -> Path:
    env = os.environ.get("INSPECTION_HOME")
    if env and Path(env, "data/version.json").exists():
        return Path(env)
    for p in ("/opt/inspection", "/seclog/AI/inspection"):
        if Path(p, "data/version.json").exists():
            return Path(p)
    raise SystemExit("找不到 inspection home")

HOME = detect_inspection_home()
VMWARE_DIR = HOME / "data" / "vmware"
CONFIG_FILE = VMWARE_DIR / "vcenters.yaml"
CREDS_VAULT = VMWARE_DIR / "vc_credentials.vault"
VAULT_PASS = HOME / ".vault_pass"
LOG_DIR = HOME / "logs"
LOG_DIR.mkdir(parents=True, exist_ok=True)

# ============================================================
#  Logging
# ============================================================
log = logging.getLogger("vmware_collector")


def setup_logging(verbose: bool = False):
    log_file = LOG_DIR / "vcenter_collector.log"
    fmt = "%(asctime)s %(levelname)s %(message)s"
    log.setLevel(logging.DEBUG if verbose else logging.INFO)
    fh = logging.FileHandler(log_file, encoding="utf-8")
    fh.setFormatter(logging.Formatter(fmt))
    log.addHandler(fh)
    sh = logging.StreamHandler()
    sh.setFormatter(logging.Formatter(fmt))
    log.addHandler(sh)


# ============================================================
#  Config / Credentials
# ============================================================
def load_vcenters_yaml() -> list[dict]:
    """讀 VC 清單 (plaintext)。格式見 vcenters.yaml.sample。"""
    if not CONFIG_FILE.exists():
        raise SystemExit(f"找不到設定檔: {CONFIG_FILE}\n請從 {CONFIG_FILE}.sample 複製後填入")
    with open(CONFIG_FILE, encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    vcenters = cfg.get("vcenters", [])
    if not vcenters:
        raise SystemExit(f"{CONFIG_FILE} 沒有 vcenters 清單")
    return vcenters


def load_credentials() -> tuple[str, str]:
    """從 ansible-vault 解密 VC 帳密。回傳 (user, password)。"""
    if not CREDS_VAULT.exists():
        raise SystemExit(f"找不到 vault: {CREDS_VAULT}\n用 ansible-vault create 建立, 格式: user/password 兩個 key")
    if not VAULT_PASS.exists():
        raise SystemExit(f"找不到 vault 密碼檔: {VAULT_PASS}")

    try:
        result = subprocess.run(
            [
                "ansible-vault", "view",
                str(CREDS_VAULT),
                "--vault-password-file", str(VAULT_PASS),
            ],
            capture_output=True, text=True, check=True, timeout=10
        )
    except subprocess.CalledProcessError as e:
        raise SystemExit(f"ansible-vault 解密失敗: {e.stderr}")
    except subprocess.TimeoutExpired:
        raise SystemExit("ansible-vault 解密 timeout")

    try:
        creds = yaml.safe_load(result.stdout)
        return creds["user"], creds["password"]
    except (yaml.YAMLError, KeyError) as e:
        raise SystemExit(f"vault 內容格式錯 (要 user/password 兩個 key): {e}")


# ============================================================
#  VC 連線 (read-only)
# ============================================================
def connect_vc(host: str, user: str, pwd: str, timeout: int = 30):
    """SmartConnect + SSL cert bypass + read-only 宣告。"""
    ctx = ssl._create_unverified_context()
    try:
        si = SmartConnect(
            host=host, user=user, pwd=pwd,
            sslContext=ctx, disableSslCertValidation=True,
            connectionPoolTimeout=timeout,
        )
    except TypeError:
        si = SmartConnect(host=host, user=user, pwd=pwd, sslContext=ctx)
    return si


def collect_clusters(content) -> list[dict]:
    """讀所有 Cluster (read-only: summary + config)。ContainerView 用完 Destroy。"""
    view = content.viewManager.CreateContainerView(
        content.rootFolder, [vim.ClusterComputeResource], True
    )
    try:
        out = []
        for cluster in view.view:
            try:
                s = cluster.summary
                cpu_total = s.totalCpu or 0
                cpu_used = (s.effectiveCpu or 0)
                mem_total_mb = (s.totalMemory or 0) // (1024 * 1024)
                mem_effective_mb = (s.effectiveMemory or 0)  # already MB

                cfg = cluster.configurationEx
                ha_enabled = bool(cfg.dasConfig and cfg.dasConfig.enabled) if cfg else False
                drs_enabled = bool(cfg.drsConfig and cfg.drsConfig.enabled) if cfg else False

                out.append({
                    "name": cluster.name,
                    "host_count": s.numHosts or 0,
                    "host_effective": s.numEffectiveHosts or 0,
                    "cpu_total_mhz": cpu_total,
                    "cpu_effective_mhz": cpu_used,
                    "cpu_pct": round(100 * (cpu_total - cpu_used) / cpu_total, 1) if cpu_total else 0,
                    "mem_total_mb": mem_total_mb,
                    "mem_effective_mb": mem_effective_mb,
                    "mem_pct": round(100 * (mem_total_mb - mem_effective_mb) / mem_total_mb, 1) if mem_total_mb else 0,
                    "ha_enabled": ha_enabled,
                    "drs_enabled": drs_enabled,
                    "overall_status": str(s.overallStatus) if s.overallStatus else None,
                })
            except Exception as e:
                log.warning(f"Cluster {cluster.name} 讀取失敗: {e}")
        return out
    finally:
        view.Destroy()


def collect_hosts(content) -> list[dict]:
    """讀所有 ESXi Host (read-only: summary + quickStats + hardware + config.product)。"""
    view = content.viewManager.CreateContainerView(
        content.rootFolder, [vim.HostSystem], True
    )
    try:
        out = []
        for h in view.view:
            try:
                qs = h.summary.quickStats
                hw = h.hardware
                runtime = h.runtime
                parent_name = h.parent.name if h.parent else None

                cpu_total = 0
                if hw and hw.cpuInfo:
                    cpu_total = (hw.cpuInfo.hz // 1_000_000) * hw.cpuInfo.numCpuCores
                cpu_used = qs.overallCpuUsage or 0
                mem_total_mb = (hw.memorySize // (1024 * 1024)) if hw else 0
                mem_used_mb = qs.overallMemoryUsage or 0

                product = h.config.product if h.config else None
                out.append({
                    "name": h.name,
                    "cluster": parent_name,
                    "cpu_total_mhz": cpu_total,
                    "cpu_used_mhz": cpu_used,
                    "cpu_pct": round(100 * cpu_used / cpu_total, 1) if cpu_total else 0,
                    "mem_total_mb": mem_total_mb,
                    "mem_used_mb": mem_used_mb,
                    "mem_pct": round(100 * mem_used_mb / mem_total_mb, 1) if mem_total_mb else 0,
                    "version": product.version if product else None,
                    "build": product.build if product else None,
                    "full_name": product.fullName if product else None,
                    "connection_state": str(runtime.connectionState) if runtime else None,
                    "power_state": str(runtime.powerState) if runtime else None,
                    "overall_status": str(h.summary.overallStatus) if h.summary.overallStatus else None,
                    "uptime_seconds": qs.uptime or 0,
                })
            except Exception as e:
                log.warning(f"Host {getattr(h, 'name', '?')} 讀取失敗: {e}")
        return out
    finally:
        view.Destroy()


def collect_one_vcenter(vc: dict, user: str, pwd: str) -> dict:
    """連一個 VC 抓所有資料, 回傳 snapshot dict。失敗也回傳 dict (status=fail)。"""
    label = vc["label"]
    ip = vc["ip"]
    snapshot = {
        "timestamp": datetime.utcnow(),
        "vcenter": {"label": label, "ip": ip},
        "status": "unknown",
        "error": None,
        "about": None,
        "clusters": [],
        "hosts": [],
        "collector_version": "3.12.1.0",
    }

    log.info(f"[{label}] {ip} 開始連線")
    si = None
    try:
        si = connect_vc(ip, user, pwd)
        content = si.RetrieveContent()
        about = content.about
        snapshot["about"] = {
            "version": about.version,
            "build": about.build,
            "full_name": about.fullName,
            "api_version": about.apiVersion,
        }
        log.info(f"[{label}] 登入成功: {about.fullName}")

        snapshot["clusters"] = collect_clusters(content)
        log.info(f"[{label}] 取得 {len(snapshot['clusters'])} Cluster")

        snapshot["hosts"] = collect_hosts(content)
        log.info(f"[{label}] 取得 {len(snapshot['hosts'])} Host")

        snapshot["status"] = "success"
    except Exception as e:
        snapshot["status"] = "fail"
        snapshot["error"] = f"{type(e).__name__}: {e}"
        log.error(f"[{label}] 失敗: {snapshot['error']}")
    finally:
        if si is not None:
            try:
                Disconnect(si)
            except Exception:
                pass

    return snapshot


# ============================================================
#  MongoDB
# ============================================================
def get_mongo_db():
    client = MongoClient("localhost", 27017, serverSelectionTimeoutMS=5000)
    return client["inspection"]


def write_snapshots(db, snapshots: list[dict]):
    """寫快照到 vmware_snapshots collection。"""
    col = db["vmware_snapshots"]
    # 確保 index (idempotent)
    col.create_index([("timestamp", DESCENDING), ("vcenter.ip", ASCENDING)])
    col.create_index([("vcenter.ip", ASCENDING), ("timestamp", DESCENDING)])
    # TTL: 180 天
    try:
        col.create_index(
            [("timestamp", ASCENDING)],
            expireAfterSeconds=180 * 86400,
            name="ttl_180d"
        )
    except Exception:
        pass  # already exists

    result = col.insert_many(snapshots)
    log.info(f"MongoDB 寫入 {len(result.inserted_ids)} 筆 snapshot")


# ============================================================
#  Mock snapshot generator (家裡 221 測 pipeline 用)
# ============================================================
def generate_mock_snapshots() -> list[dict]:
    """產生 5 VC 的 mock snapshots, 資料結構跟真 collector 一致。"""
    import random
    now = datetime.utcnow()

    def _host(cluster, idx, ver, build, cpu_total=102400, cpu_pct=None, status="ok"):
        cpu_pct = cpu_pct if cpu_pct is not None else random.randint(15, 55)
        cpu_used = int(cpu_total * cpu_pct / 100)
        mem_total = 524288
        mem_used = int(mem_total * random.randint(45, 70) / 100)
        return {
            "name": f"esxi-{cluster.lower().replace('_','-')}-{idx:02d}.xxx",
            "cluster": cluster,
            "cpu_total_mhz": cpu_total, "cpu_used_mhz": cpu_used, "cpu_pct": cpu_pct,
            "mem_total_mb": mem_total, "mem_used_mb": mem_used,
            "mem_pct": round(100 * mem_used / mem_total, 1),
            "version": ver, "build": build,
            "full_name": f"VMware ESXi {ver} build-{build}",
            "connection_state": "connected", "power_state": "poweredOn",
            "overall_status": status, "uptime_seconds": 86400 * 45,
        }

    def _cluster(name, host_count, ver, build, cpu_pct, status="green"):
        return {
            "name": name, "host_count": host_count, "host_effective": host_count,
            "cpu_total_mhz": 102400 * host_count, "cpu_effective_mhz": int(102400 * host_count * (100 - cpu_pct) / 100),
            "cpu_pct": cpu_pct,
            "mem_total_mb": 524288 * host_count, "mem_effective_mb": int(524288 * host_count * 0.45),
            "mem_pct": 55.0,
            "ha_enabled": True, "drs_enabled": True,
            "overall_status": status,
        }

    # 5 個 VC, 基於公司 PPT 的真實 cluster 配置
    vc_configs = [
        {
            "label": "板橋", "location": "板橋", "ip": "10.93.169.191",
            "about": {"version": "8.0.3", "build": "24280767", "full_name": "VMware vCenter Server 8.0.3 build-24280767", "api_version": "8.0.3.0"},
            "clusters": [
                ("BQ_PROD_A_vSan_Cluster", 10, "8.0.3", "24280767", 42),
                ("BQ_PROD_B_vSan_Cluster", 10, "8.0.3", "24280767", 38),
                ("BQ_PROD_Cluster01",       5, "7.0.3", "23794027", 78),
                ("BQ_PROD_Cluster02",       5, "7.0.3", "23794027", 82),
                ("BQ_PROD_LOG_Cluster",     8, "8.0.3", "24585383", 24),
            ],
        },
        {
            "label": "內湖-1", "location": "內湖", "ip": "10.93.3.191",
            "about": {"version": "8.0.3", "build": "24859861", "full_name": "VMware vCenter Server 8.0.3 build-24859861", "api_version": "8.0.3.0"},
            "clusters": [
                ("NH_PROD_Cluster01",    4, "8.0.3", "24859861", 48),
                ("NH_PROD_Cluster02",    4, "8.0.3", "24859861", 52),
                ("NH_PROD_UAT_Cluster01", 2, "7.0.3", "22348816", 32),
            ],
        },
        {
            "label": "內湖-2", "location": "內湖", "ip": "10.93.198.121",
            "about": {"version": "7.0.3", "build": "21930508", "full_name": "VMware vCenter Server 7.0.3 build-21930508", "api_version": "7.0.3.0"},
            "clusters": [
                ("NH_PROD_vSAN_Cluster01", 6, "7.0.3", "21930508", 54),
                ("NH_UAT_vSAN_Cluster02",  4, "7.0.3", "21930508", 28),
            ],
        },
        {
            "label": "VCF", "location": "內湖", "ip": "10.93.199.191",
            "about": {"version": "8.0.3", "build": "24280767", "full_name": "VMware vCenter Server 8.0.3 build-24280767", "api_version": "8.0.3.0"},
            "clusters": [
                ("VCF_Prod_vSAN_Cluster01",    4, "8.0.3", "24280767", 44),
                ("VCF-WLD02-UAT-CL01-DC",      6, "8.0.3", "24280767", 22),
            ],
        },
        {
            "label": "敦南", "location": "敦南", "ip": "10.93.19.191",
            "about": {"version": "8.0.3", "build": "24585383", "full_name": "VMware vCenter Server 8.0.3 build-24585383", "api_version": "8.0.3.0"},
            "clusters": [
                ("DN_PROD_Cluster01", 6, "8.0.3", "24585383", 56),
                ("DN_UAT_Cluster01",  4, "8.0.3", "25205845", 18),
            ],
        },
    ]

    snapshots = []
    for vc in vc_configs:
        clusters_data = []
        hosts_data = []
        for cname, hcount, ver, build, cpu_pct in vc["clusters"]:
            clusters_data.append(_cluster(cname, hcount, ver, build, cpu_pct))
            for i in range(1, hcount + 1):
                hosts_data.append(_host(cname, i, ver, build, cpu_pct=cpu_pct + random.randint(-10, 10)))

        snapshots.append({
            "timestamp": now,
            "vcenter": {"label": vc["label"], "location": vc["location"], "ip": vc["ip"]},
            "status": "success",
            "error": None,
            "about": vc["about"],
            "clusters": clusters_data,
            "hosts": hosts_data,
            "collector_version": "3.12.1.0",
            "mock": True,
        })

    return snapshots


# ============================================================
#  Main
# ============================================================
def main():
    parser = argparse.ArgumentParser(description="VMware vCenter Collector")
    parser.add_argument("--only", help="只跑指定 label 的 VC", default=None)
    parser.add_argument("--dry-run", action="store_true", help="不寫 MongoDB")
    parser.add_argument("--mock-write", action="store_true", help="不連 VC, 寫 mock snapshots 到 MongoDB")
    parser.add_argument("--verbose", "-v", action="store_true", help="更多 log")
    args = parser.parse_args()

    setup_logging(args.verbose)

    log.info("=" * 60)
    log.info("VMware Collector 開始 (v3.12.1.0)")
    log.info(f"INSPECTION_HOME = {HOME}")
    log.info(f"dry_run = {args.dry_run}, only = {args.only}, mock_write = {args.mock_write}")

    # ===== Mock-write 模式 =====
    if args.mock_write:
        log.info("=== MOCK-WRITE 模式: 不連 VC, 產生 mock snapshots ===")
        snapshots = generate_mock_snapshots()
        ok = len(snapshots)
        fail = 0
        log.info(f"產生 {ok} 筆 mock snapshot (5 VC)")
        try:
            db = get_mongo_db()
            write_snapshots(db, snapshots)
        except Exception as e:
            log.error(f"MongoDB 寫入失敗: {e}")
            sys.exit(2)
        log.info("Mock snapshots 已寫入 MongoDB")
        sys.exit(0)

    # ===== 正常 / dry-run 模式 =====
    vcenters = load_vcenters_yaml()
    user, pwd = load_credentials()
    log.info(f"帳號: {user}")
    log.info(f"VC 清單: {len(vcenters)} 筆")

    if args.only:
        vcenters = [v for v in vcenters if v["label"] == args.only]
        if not vcenters:
            raise SystemExit(f"--only {args.only} 在 vcenters.yaml 找不到")

    snapshots = []
    for vc in vcenters:
        snap = collect_one_vcenter(vc, user, pwd)
        snapshots.append(snap)

    # 統計
    ok = sum(1 for s in snapshots if s["status"] == "success")
    fail = len(snapshots) - ok
    log.info(f"完成: {ok}/{len(snapshots)} VC 成功, {fail} 失敗")

    if args.dry_run:
        log.info("--dry-run, 不寫 MongoDB")
        # 輸出 dry-run summary
        for s in snapshots:
            print(json.dumps({
                "vcenter": s["vcenter"],
                "status": s["status"],
                "error": s.get("error"),
                "cluster_count": len(s["clusters"]),
                "host_count": len(s["hosts"]),
                "about": s.get("about"),
            }, default=str, ensure_ascii=False, indent=2))
    else:
        try:
            db = get_mongo_db()
            write_snapshots(db, snapshots)
        except Exception as e:
            log.error(f"MongoDB 寫入失敗: {e}")
            sys.exit(2)

    log.info("Collector 結束")
    sys.exit(0 if fail == 0 else 1)


if __name__ == "__main__":
    main()
