"""
subnet_service.py - 網段管理 (P3 of CMDB, IPAM 簡化版)
功能: subnets CRUD + 自動算每段使用率 (從 hosts.ips 比對 CIDR)
"""
import ipaddress
from datetime import datetime
from services.mongo_service import get_collection


def ensure_indexes():
    col = get_collection("subnets")
    col.create_index([("cidr", 1)], unique=True)
    col.create_index([("env", 1)])
    col.create_index([("location", 1)])


def list_subnets():
    col = get_collection("subnets")
    docs = list(col.find({}, {"_id": 0}).sort("cidr", 1))
    # 自動補使用率
    for s in docs:
        usage = compute_usage(s.get("cidr", ""))
        s.update(usage)
    return docs


def get_subnet(cidr):
    s = get_collection("subnets").find_one({"cidr": cidr}, {"_id": 0})
    if s:
        s.update(compute_usage(cidr))
    return s


def create_subnet(doc, who="admin"):
    cidr = (doc.get("cidr") or "").strip()
    if not cidr:
        return False, "cidr 必填"
    # validate CIDR
    try:
        ipaddress.ip_network(cidr, strict=False)
    except ValueError as e:
        return False, f"CIDR 格式錯誤: {e}"
    col = get_collection("subnets")
    if col.find_one({"cidr": cidr}):
        return False, f"網段 {cidr} 已存在"
    now = datetime.now().isoformat()
    payload = {
        "cidr": cidr,
        "vlan": int(doc.get("vlan") or 0),
        "env": doc.get("env") or "",
        "location": doc.get("location") or "",
        "purpose": doc.get("purpose") or "",
        "gateway": doc.get("gateway") or "",
        "notes": doc.get("notes") or "",
        "created_at": now,
        "updated_at": now,
        "created_by": who,
    }
    col.insert_one(payload)
    return True, f"網段 {cidr} 已建立"


def update_subnet(cidr, updates, who="admin"):
    col = get_collection("subnets")
    if not col.find_one({"cidr": cidr}):
        return False, f"網段 {cidr} 不存在"
    upd = {k: v for k, v in updates.items() if k in ("vlan", "env", "location", "purpose", "gateway", "notes")}
    if "vlan" in upd:
        try:
            upd["vlan"] = int(upd["vlan"])
        except (ValueError, TypeError):
            upd["vlan"] = 0
    upd["updated_at"] = datetime.now().isoformat()
    upd["updated_by"] = who
    col.update_one({"cidr": cidr}, {"$set": upd})
    return True, f"網段 {cidr} 已更新"


def delete_subnet(cidr):
    col = get_collection("subnets")
    r = col.delete_one({"cidr": cidr})
    if r.deleted_count == 0:
        return False, f"網段 {cidr} 不存在"
    return True, f"網段 {cidr} 已刪除"


def _all_host_ips():
    """從 hosts collection 撈所有 IP, 回 [(ip_str, hostname), ...]"""
    out = []
    for h in get_collection("hosts").find({}, {"_id": 0, "hostname": 1, "ip": 1, "ips": 1}):
        seen = set()
        for ip in (h.get("ips") or []) + ([h.get("ip")] if h.get("ip") else []):
            if ip and ip not in seen:
                seen.add(ip)
                out.append((ip, h.get("hostname")))
    return out


def compute_usage(cidr):
    """算某網段的 IP 使用率
    Returns: {total, used, used_ips: [{ip, hostname}], available, percent}
    """
    if not cidr:
        return {"total": 0, "used": 0, "used_ips": [], "available": 0, "percent": 0}
    try:
        net = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        return {"total": 0, "used": 0, "used_ips": [], "available": 0, "percent": 0, "error": "invalid CIDR"}

    total = max(0, net.num_addresses - 2) if net.num_addresses > 2 else net.num_addresses
    used_ips = []
    for ip_str, hn in _all_host_ips():
        try:
            ip = ipaddress.ip_address(ip_str)
            if ip in net:
                used_ips.append({"ip": ip_str, "hostname": hn})
        except ValueError:
            continue
    used = len(used_ips)
    available = max(0, total - used)
    percent = round((used / total * 100), 1) if total > 0 else 0
    return {
        "total": total,
        "used": used,
        "used_ips": used_ips,
        "available": available,
        "percent": percent,
    }


def next_available_ip(cidr):
    """找該網段下一個可用 IP (簡化版: 排除網段+廣播+已使用)"""
    try:
        net = ipaddress.ip_network(cidr, strict=False)
    except ValueError:
        return None
    used = set(item["ip"] for item in compute_usage(cidr)["used_ips"])
    for host_ip in net.hosts():
        if str(host_ip) not in used:
            return str(host_ip)
    return None
