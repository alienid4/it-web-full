"""
host_dedup.py - 重複/相似主機偵測 (P2 of CMDB 整合)
偵測規則:
  1. hostname 相似度 (difflib.SequenceMatcher ratio >= 0.7)
  2. 一個 hostname 出現在對方 aliases 內
  3. 共用 IP
"""
import difflib
from services.mongo_service import get_collection


def _all_ips(h):
    """收集 host 所有 IP (主 ip + ips array)"""
    ips = set()
    if h.get("ip"):
        ips.add(h["ip"])
    for x in h.get("ips") or []:
        if x:
            ips.add(x)
    return ips


def find_similar_hosts(threshold_ratio=0.7):
    """找出疑似重複的主機對, score 高到低排序

    Returns: list of {host1, host2, score, reasons, h1_data, h2_data}
    """
    hosts = list(get_collection("hosts").find({}, {"_id": 0}))
    pairs = []

    for i in range(len(hosts)):
        h1 = hosts[i]
        h1_aliases = h1.get("aliases") or []
        h1_ips = _all_ips(h1)
        for j in range(i + 1, len(hosts)):
            h2 = hosts[j]
            h2_aliases = h2.get("aliases") or []
            h2_ips = _all_ips(h2)

            reasons = []
            score = 0

            # 1. hostname Levenshtein-like ratio
            r = difflib.SequenceMatcher(
                None, h1["hostname"].lower(), h2["hostname"].lower()
            ).ratio()
            if r >= threshold_ratio:
                reasons.append(f"hostname 相似度 {int(r * 100)}%")
                score += int(r * 100)

            # 2. hostname 在對方 aliases
            if h1["hostname"] in h2_aliases:
                reasons.append(f"{h1['hostname']} 是 {h2['hostname']} 的別名")
                score += 100
            if h2["hostname"] in h1_aliases:
                reasons.append(f"{h2['hostname']} 是 {h1['hostname']} 的別名")
                score += 100

            # 3. 共用 IP
            common_ips = h1_ips & h2_ips
            if common_ips:
                reasons.append(f"共用 IP: {', '.join(sorted(common_ips))}")
                score += 50 * len(common_ips)

            if reasons:
                pairs.append({
                    "host1": h1["hostname"],
                    "host2": h2["hostname"],
                    "score": score,
                    "reasons": reasons,
                    "h1_data": {
                        "ip": h1.get("ip", ""),
                        "ips": h1.get("ips") or [],
                        "asset_seq": h1.get("asset_seq", ""),
                        "system_name": h1.get("system_name", ""),
                        "aliases": h1_aliases,
                    },
                    "h2_data": {
                        "ip": h2.get("ip", ""),
                        "ips": h2.get("ips") or [],
                        "asset_seq": h2.get("asset_seq", ""),
                        "system_name": h2.get("system_name", ""),
                        "aliases": h2_aliases,
                    },
                })

    pairs.sort(key=lambda p: -p["score"])
    return pairs


def merge_hosts(primary_hostname, duplicate_hostname):
    """把 duplicate 的 hostname / ips / aliases 合併到 primary, 刪除 duplicate
    Returns: (success: bool, message: str)
    """
    col = get_collection("hosts")
    primary = col.find_one({"hostname": primary_hostname})
    duplicate = col.find_one({"hostname": duplicate_hostname})
    if not primary:
        return False, f"主紀錄 {primary_hostname} 不存在"
    if not duplicate:
        return False, f"次紀錄 {duplicate_hostname} 不存在"
    if primary_hostname == duplicate_hostname:
        return False, "primary 與 duplicate 相同, 無法合併"

    # 合併 aliases (含 duplicate 的 hostname)
    new_aliases = list(primary.get("aliases") or [])
    if duplicate_hostname not in new_aliases:
        new_aliases.append(duplicate_hostname)
    for a in duplicate.get("aliases") or []:
        if a not in new_aliases and a != primary_hostname:
            new_aliases.append(a)

    # 合併 ips (union)
    new_ips = list(primary.get("ips") or ([primary["ip"]] if primary.get("ip") else []))
    for ip in (duplicate.get("ips") or []) + ([duplicate["ip"]] if duplicate.get("ip") else []):
        if ip and ip not in new_ips:
            new_ips.append(ip)

    col.update_one(
        {"hostname": primary_hostname},
        {"$set": {"aliases": new_aliases, "ips": new_ips}},
    )
    col.delete_one({"hostname": duplicate_hostname})
    return True, f"已將 {duplicate_hostname} 合併進 {primary_hostname} (aliases +1, ips +{len(new_ips) - len(primary.get('ips') or [])})"
