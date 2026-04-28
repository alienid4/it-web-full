#!/usr/bin/env python3
"""
系統聯通圖 - ss 採集結果解析 & 灌 MongoDB (v3.15.0.0+)

讀 data/reports/connections_*.json (collect_connections.yml 產出),解析 ss raw,
反查 hosts collection 把 IP 對應到 hostname → system_id,upsert 到
dependency_relations,標記 source=ss-tunp。

噪音過濾:
  - localhost (127.x, ::1)
  - 自己 IP self-loop
  - 預設 ignore_ports (22/53/123/9090/27017 含外部 cdn 7844)
  - 找不到 system 對應 → 暫存為 UNKNOWN-<ip> 待人工確認

用法:
    python3 dependency_seed_collect.py                  # 處理 reports/connections_*.json
    python3 dependency_seed_collect.py --since 600     # 只處理最近 10 分鐘的 report
    python3 dependency_seed_collect.py --dry-run       # 不寫 DB,只 print 統計
"""
import os
import sys
import re
import json
import glob
import argparse
import ipaddress
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
WEBAPP = os.path.normpath(os.path.join(HERE, "..", "webapp"))
sys.path.insert(0, WEBAPP)

from services.mongo_service import get_collection, get_hosts_col
from services import dependency_service

INSPECTION_HOME = os.environ.get("INSPECTION_HOME", "/opt/inspection")
REPORTS_DIR = os.path.join(INSPECTION_HOME, "data", "reports")

# 預設過濾 (可被 metadata 覆蓋)
IGNORE_LOCAL_PORTS = {22, 53, 123, 5044, 9090, 9100, 27017}
IGNORE_REMOTE_PORTS = {53, 123}  # DNS/NTP 對端,通常沒分析意義
IGNORE_LOCAL_CIDRS = ["127.0.0.0/8", "::1/128", "169.254.0.0/16"]

# 已知外部系統 IP / CIDR -> 對應 system_id (預先註冊好,UI 才不會冒出 UNKNOWN-x.x.x.x)
KNOWN_EXTERNAL = [
    # cloudflared edge IPs (cloudflare CDN tunnel)
    ("198.41.0.0/16",     "EXT-CLOUDFLARE", "Cloudflare CDN/Tunnel"),
    ("162.159.0.0/16",    "EXT-CLOUDFLARE", "Cloudflare CDN/Tunnel"),
    # Google DNS / public
    ("8.8.0.0/16",        "EXT-GOOGLE-DNS", "Google Public DNS"),
    # Cloudflare 1.1.1.1
    ("1.1.1.0/24",        "EXT-CLOUDFLARE-DNS", "Cloudflare DNS"),
]


def _parse_ss_line(line, mode):
    """解析一行 ss 輸出, mode='listen' or 'estab'

    listen format (ss -tunlp -H -n):
      tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=...,fd=...))
      udp UNCONN 0 0   *:43011 *:* users:(("cloudflared",pid=...,fd=...))

    estab format (ss -tunp -H -n state established):
      tcp 0 0 192.168.1.221:22 192.168.1.103:64699 users:(("sshd",...))
    """
    line = line.strip()
    if not line:
        return None
    parts = line.split()
    try:
        if mode == "listen":
            # tcp LISTEN 0 128 LOCAL REMOTE users:(...)
            if len(parts) < 6:
                return None
            proto = parts[0].lower()
            if parts[1].upper() not in ("LISTEN", "UNCONN"):
                return None
            local = parts[4]
            users = " ".join(parts[6:]) if len(parts) > 6 else ""
        else:  # estab
            # tcp 0 0 LOCAL REMOTE users:(...)
            if len(parts) < 5:
                return None
            proto = parts[0].lower()
            local = parts[3]
            remote = parts[4]
            users = " ".join(parts[5:]) if len(parts) > 5 else ""
    except IndexError:
        return None

    # 解析 addr:port (IPv6 帶 [] 的也要處理)
    def split_ap(s):
        if s.startswith("["):
            m = re.match(r"\[([^\]]+)\]:(.+)$", s)
            if m:
                return m.group(1), m.group(2)
        if "%" in s:  # fe80::xxxx%ens160
            s = s.split("%", 1)[0]
        if ":" in s:
            host, port = s.rsplit(":", 1)
            return host, port
        return s, ""

    # 解析 process
    proc = ""
    pid = ""
    m = re.search(r'users:\(\(\"([^"]+)\",pid=(\d+)', users)
    if m:
        proc = m.group(1)
        pid = m.group(2)

    if mode == "listen":
        local_ip, local_port = split_ap(local)
        return {
            "proto": proto,
            "local_ip": local_ip,
            "local_port": _parse_port(local_port),
            "process": proc,
            "pid": pid,
        }
    else:
        local_ip, local_port = split_ap(local)
        remote_ip, remote_port = split_ap(remote)
        return {
            "proto": proto,
            "local_ip": local_ip,
            "local_port": _parse_port(local_port),
            "remote_ip": remote_ip,
            "remote_port": _parse_port(remote_port),
            "process": proc,
            "pid": pid,
        }


def _parse_port(s):
    try:
        return int(s)
    except (ValueError, TypeError):
        return 0


def _is_local_addr(ip, host_ip):
    if not ip or ip == "*":
        return True
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    for cidr in IGNORE_LOCAL_CIDRS:
        if addr in ipaddress.ip_network(cidr):
            return True
    if host_ip and ip == host_ip:
        return True
    return False


def _classify_external(ip):
    """如果是已知外部系統,回 (system_id, display_name);否則 None"""
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return None
    for cidr, sid, name in KNOWN_EXTERNAL:
        if addr in ipaddress.ip_network(cidr):
            return sid, name
    return None


def _build_host_lookups():
    """從 hosts collection + dependency_systems 建立反查表

    Returns:
      ip_to_host: {ip: hostname}
      hostname_to_systems: {hostname: [system_id, ...]} (一台主機可屬多個系統)
    """
    ip_to_host = {}
    for h in get_hosts_col().find({}, {"_id": 0, "hostname": 1, "ip": 1}):
        if h.get("ip"):
            ip_to_host[h["ip"]] = h["hostname"]

    hostname_to_systems = {}
    for s in get_collection("dependency_systems").find({}, {"_id": 0, "system_id": 1, "host_refs": 1}):
        for h in s.get("host_refs", []) or []:
            hostname_to_systems.setdefault(h, []).append(s["system_id"])

    return ip_to_host, hostname_to_systems


def _ensure_external_systems():
    """確保 KNOWN_EXTERNAL 對應的 system_id 在 dependency_systems 內"""
    sys_col = get_collection("dependency_systems")
    seen_sids = set()
    for cidr, sid, name in KNOWN_EXTERNAL:
        if sid in seen_sids:
            continue
        seen_sids.add(sid)
        if not sys_col.find_one({"system_id": sid}):
            sys_col.insert_one({
                "system_id": sid,
                "display_name": name,
                "tier": "C",
                "category": "External",
                "owner": "(自動採集)",
                "host_refs": [],
                "external": True,
                "description": f"已知外部 IP 段 {cidr},自動標記",
                "metadata": {"auto_added": True, "cidr": cidr},
                "created_at": datetime.utcnow(),
                "updated_at": datetime.utcnow(),
                "created_by": "ss_collect",
            })


def _ensure_unknown_system(remote_ip):
    """為找不到 hostname 的 IP 建一個 UNKNOWN-<ip> 系統節點"""
    sid = f"UNKNOWN-{remote_ip}"
    sys_col = get_collection("dependency_systems")
    if not sys_col.find_one({"system_id": sid}):
        sys_col.insert_one({
            "system_id": sid,
            "display_name": f"未知 {remote_ip}",
            "tier": "C",
            "category": "External",
            "owner": "(待確認)",
            "host_refs": [],
            "external": True,
            "description": f"ss 採集發現的對端 {remote_ip},反查不到 hosts collection,請人工分類",
            "metadata": {"auto_added": True, "ip": remote_ip},
            "created_at": datetime.utcnow(),
            "updated_at": datetime.utcnow(),
            "created_by": "ss_collect",
        })
    return sid


def _resolve_target_system(remote_ip, ip_to_host, hostname_to_systems):
    """回傳 (target_system_id, label, hint)"""
    # 1. 已知外部
    ext = _classify_external(remote_ip)
    if ext:
        return ext[0], "external", ext[1]
    # 2. hosts.ip → hostname → system
    hostname = ip_to_host.get(remote_ip)
    if hostname:
        sids = hostname_to_systems.get(hostname, [])
        if sids:
            # 一台主機若屬多系統,先選 tier A 的;簡化:直接第一個
            return sids[0], "internal", hostname
        else:
            # 主機在 hosts 內但沒被任何 system 涵蓋
            return None, "uncovered_host", hostname
    # 3. 私網但反查不到 → UNKNOWN-<ip>
    return _ensure_unknown_system(remote_ip), "unknown", remote_ip


def process_report(report_path, dry_run=False):
    """處理單份 connections_*.json"""
    with open(report_path, encoding="utf-8") as f:
        report = json.load(f)

    host = report.get("host", "")
    host_ip = report.get("ip", "")
    collected_at = report.get("collected_at") or datetime.utcnow().isoformat()
    listen_raw = report.get("listen_raw", "")
    estab_raw = report.get("estab_raw", "")

    listening = []
    for line in listen_raw.split("\n"):
        p = _parse_ss_line(line, "listen")
        if p and not _is_local_addr(p["local_ip"], None):
            listening.append(p)

    established = []
    for line in estab_raw.split("\n"):
        p = _parse_ss_line(line, "estab")
        if not p:
            continue
        # 過濾 localhost-only
        if _is_local_addr(p["local_ip"], host_ip) and _is_local_addr(p["remote_ip"], host_ip):
            continue
        established.append(p)

    # 反查 hosts / systems
    ip_to_host, hostname_to_systems = _build_host_lookups()
    _ensure_external_systems()

    # 找出來源 system (host 所屬)
    src_systems = hostname_to_systems.get(host, [])
    if not src_systems:
        # host 沒被任何 system 涵蓋,先放棄
        return {
            "host": host,
            "skipped": "host 不屬於任何 dependency_system,請先建立",
            "listen_count": len(listening),
            "estab_count": len(established),
            "edges_added": 0,
            "edges_updated": 0,
        }

    rel_col = get_collection("dependency_relations")
    edges_added = 0
    edges_updated = 0
    edges_skipped = 0
    new_unknowns = set()

    for conn in established:
        remote_ip = conn["remote_ip"]
        remote_port = conn["remote_port"]
        proto = conn["proto"]

        # remote 也是 local IP (loopback) 跳
        if _is_local_addr(remote_ip, host_ip):
            edges_skipped += 1
            continue

        # 分類對端
        target_sid, kind, hint = _resolve_target_system(remote_ip, ip_to_host, hostname_to_systems)
        if not target_sid:
            edges_skipped += 1
            continue
        if kind == "unknown":
            new_unknowns.add(remote_ip)

        # 對每個來源 system (host_refs 多 system 的場景),建一條邊
        for src_sid in src_systems:
            if src_sid == target_sid:
                continue  # 自己連自己跳

            # 過濾 ignore ports
            if remote_port in IGNORE_LOCAL_PORTS and target_sid != "EXT-CLOUDFLARE":
                # cloudflared 連 7844 例外保留
                if remote_port not in (7844,):
                    edges_skipped += 1
                    continue

            edge_doc = {
                "from_system": src_sid,
                "to_system": target_sid,
                "relation_type": "network",
                "protocol": proto.upper(),
                "port": remote_port,
            }
            existing = rel_col.find_one(edge_doc)
            now = datetime.utcnow()
            evidence_update = {
                "evidence.last_seen_at": now,
                "evidence.last_remote_ip": remote_ip,
                "evidence.last_process": conn.get("process", ""),
                "updated_at": now,
            }
            if existing:
                if dry_run:
                    pass
                else:
                    rel_col.update_one(
                        {"_id": existing["_id"]},
                        {
                            "$set": evidence_update,
                            "$inc": {"evidence.seen_count": 1},
                            "$addToSet": {"evidence.sample_hosts": host},
                        },
                    )
                edges_updated += 1
            else:
                if dry_run:
                    pass
                else:
                    rel_col.insert_one({
                        **edge_doc,
                        "source": "ss-tunp",
                        "manual_confirmed": False,
                        "evidence": {
                            "first_seen_at": now,
                            "last_seen_at": now,
                            "seen_count": 1,
                            "last_remote_ip": remote_ip,
                            "last_process": conn.get("process", ""),
                            "sample_hosts": [host],
                        },
                        "description": f"ss 自動偵測 ({conn.get('process','?')})",
                        "created_at": now,
                        "updated_at": now,
                        "created_by": "ss_collect",
                    })
                edges_added += 1

    return {
        "host": host,
        "host_ip": host_ip,
        "src_systems": src_systems,
        "listen_count": len(listening),
        "estab_count": len(established),
        "edges_added": edges_added,
        "edges_updated": edges_updated,
        "edges_skipped": edges_skipped,
        "new_unknowns": sorted(new_unknowns),
        "collected_at": collected_at,
    }


def _record_run(report_paths, results, status="success"):
    """寫一筆到 dependency_collect_runs"""
    now = datetime.utcnow()
    run_id = f"dep_{now.strftime('%Y%m%d_%H%M%S')}"
    total_added = sum(r.get("edges_added", 0) for r in results)
    total_updated = sum(r.get("edges_updated", 0) for r in results)
    new_unknowns = set()
    for r in results:
        new_unknowns.update(r.get("new_unknowns", []))
    get_collection("dependency_collect_runs").insert_one({
        "run_id": run_id,
        "started_at": now,
        "finished_at": now,
        "status": status,
        "report_files": [os.path.basename(p) for p in report_paths],
        "host_count": len(results),
        "edges_added": total_added,
        "edges_updated": total_updated,
        "new_unknowns": sorted(new_unknowns),
        "per_host": results,
    })
    return run_id


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--since", type=int, default=0,
                   help="只處理最近 N 秒內的 report (0 = 全部)")
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--keep-reports", action="store_true",
                   help="處理完不刪 report json (預設處理完移到 reports_archive/)")
    args = p.parse_args()

    dependency_service.ensure_indexes()

    pattern = os.path.join(REPORTS_DIR, "connections_*.json")
    files = sorted(glob.glob(pattern))
    if args.since > 0:
        cutoff = datetime.utcnow().timestamp() - args.since
        files = [f for f in files if os.path.getmtime(f) >= cutoff]

    if not files:
        print(f"[seed_collect] 沒有 connections_*.json 在 {REPORTS_DIR}")
        return

    print(f"[seed_collect] 處理 {len(files)} 份 report (dry_run={args.dry_run})")
    results = []
    for fp in files:
        try:
            r = process_report(fp, dry_run=args.dry_run)
            results.append(r)
            print(f"  - {os.path.basename(fp)}: host={r.get('host')} estab={r.get('estab_count')} added={r.get('edges_added')} updated={r.get('edges_updated')} skip={r.get('edges_skipped')}")
            if r.get("new_unknowns"):
                print(f"    new_unknowns: {r['new_unknowns']}")
        except Exception as e:
            print(f"  - {os.path.basename(fp)}: ERROR {e}")
            results.append({"host": os.path.basename(fp), "error": str(e)})

    if not args.dry_run:
        run_id = _record_run(files, results)
        print(f"[seed_collect] run_id: {run_id}")

        # 處理完搬到 archive 防止下次重複處理 (可用 --keep-reports 關掉)
        if not args.keep_reports:
            archive_dir = os.path.join(INSPECTION_HOME, "data", "reports_archive")
            os.makedirs(archive_dir, exist_ok=True)
            for fp in files:
                try:
                    os.rename(fp, os.path.join(archive_dir, os.path.basename(fp)))
                except OSError:
                    pass


if __name__ == "__main__":
    main()
