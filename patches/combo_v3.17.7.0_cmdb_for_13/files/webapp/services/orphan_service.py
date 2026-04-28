"""
orphan_service.py - 孤兒主機 + 稽核曝光 (P5 of CMDB)
不能做的: 防線 1/3/4/5 (需要 IPAM/DHCP/Switch/ITSM 整合)
能做的:
  - 防線 2 (簡化): 列出久未巡檢的主機 (stale)
  - 防線 6: 找出 IPAM subnet 內的 IP 但 hosts 沒登記 (gap report)
"""
import ipaddress
from datetime import datetime, timedelta
from services.mongo_service import get_collection


def _parse_iso(s):
    if not s: return None
    try:
        return datetime.fromisoformat(str(s).replace("Z", "").replace("T", " ").split(".")[0])
    except (ValueError, TypeError):
        return None


def find_stale_hosts(days=30):
    """找久未有巡檢紀錄的主機.
    依 inspections collection 最後一次 run_date, 或 hosts.imported_at fallback.
    """
    inspections = get_collection("inspections")
    hosts = list(get_collection("hosts").find({}, {"_id": 0}))
    threshold = datetime.now() - timedelta(days=days)
    threshold_str = threshold.strftime("%Y-%m-%d")

    out = []
    for h in hosts:
        hn = h.get("hostname")
        if not hn:
            continue
        last = inspections.find_one(
            {"hostname": hn},
            {"_id": 0, "run_date": 1, "run_time": 1},
            sort=[("run_date", -1), ("run_time", -1)],
        )
        last_date = (last or {}).get("run_date") or h.get("imported_at", "")[:10]
        d = _parse_iso(last_date) or _parse_iso(h.get("imported_at"))
        if not d or d < threshold:
            out.append({
                "hostname": hn,
                "ip": h.get("ip", ""),
                "last_seen": last_date or "(從未)",
                "days_since": (datetime.now() - d).days if d else 9999,
                "system_name": h.get("system_name", ""),
                "custodian": h.get("custodian", ""),
            })
    out.sort(key=lambda x: -x["days_since"])
    return out


def find_subnet_gaps():
    """找 IPAM subnets 內未被 hosts 登記的「可能孤兒 IP」.
    這 IP 還沒被掃過 — 但可以是「值得查一下」的清單.
    """
    subnets = list(get_collection("subnets").find({}, {"_id": 0}))
    if not subnets:
        return {"subnets_count": 0, "total_gap_ips": 0, "details": []}

    # 收 hosts 所有 IP
    used_ips = set()
    for h in get_collection("hosts").find({}, {"_id": 0, "ips": 1, "ip": 1}):
        for ip in (h.get("ips") or []) + ([h.get("ip")] if h.get("ip") else []):
            if ip:
                used_ips.add(ip)

    details = []
    total_gap = 0
    for s in subnets:
        cidr = s.get("cidr", "")
        try:
            net = ipaddress.ip_network(cidr, strict=False)
        except ValueError:
            continue
        gap_ips = []
        for ip in net.hosts():
            if str(ip) not in used_ips:
                gap_ips.append(str(ip))
        # 只回前 50 個 (太多沒意義)
        details.append({
            "cidr": cidr,
            "vlan": s.get("vlan", 0),
            "env": s.get("env", ""),
            "purpose": s.get("purpose", ""),
            "total_host_bits": net.num_addresses - 2 if net.num_addresses > 2 else net.num_addresses,
            "used": len([ip for ip in net.hosts() if str(ip) in used_ips]),
            "gap_count": len(gap_ips),
            "gap_sample": gap_ips[:20],
        })
        total_gap += len(gap_ips)

    return {
        "subnets_count": len(subnets),
        "total_gap_ips": total_gap,
        "details": details,
    }


def audit_summary(days_threshold=30):
    """月稽核曝光總覽 (給 6 號防線用)"""
    stale = find_stale_hosts(days=days_threshold)
    gaps = find_subnet_gaps()
    return {
        "generated_at": datetime.now().isoformat(),
        "stale_hosts_count": len(stale),
        "stale_hosts": stale,
        "subnet_gaps": gaps,
        "threshold_days": days_threshold,
    }
