"""
系統聯通圖 Service 層
Collections:
  - dependency_systems   : 業務系統節點 (1 system : N hosts via host_refs[])
  - dependency_relations : 系統間有向依賴邊 (from_system → to_system)
  - dependency_collect_runs : Ansible 採集執行紀錄 (Stage 3 才用)
"""
from datetime import datetime
from bson import ObjectId
from pymongo import ASCENDING, DESCENDING
from services.mongo_service import get_collection


# --------------------------------------------------------------------
# Index 初始化
# --------------------------------------------------------------------
def ensure_indexes():
    sys_col = get_collection("dependency_systems")
    sys_col.create_index([("system_id", ASCENDING)], unique=True)
    sys_col.create_index([("tier", ASCENDING)])
    sys_col.create_index([("category", ASCENDING)])
    sys_col.create_index([("host_refs", ASCENDING)])

    rel_col = get_collection("dependency_relations")
    rel_col.create_index(
        [("from_system", ASCENDING), ("to_system", ASCENDING), ("port", ASCENDING)],
        unique=True,
        name="uniq_edge",
    )
    rel_col.create_index([("from_system", ASCENDING)])
    rel_col.create_index([("to_system", ASCENDING)])
    rel_col.create_index([("source", ASCENDING)])
    rel_col.create_index([("evidence.last_seen_at", DESCENDING)])

    run_col = get_collection("dependency_collect_runs")
    run_col.create_index([("run_id", ASCENDING)], unique=True)
    run_col.create_index([("started_at", DESCENDING)])


# --------------------------------------------------------------------
# 系統節點 CRUD
# --------------------------------------------------------------------
def list_systems(tier=None, category=None):
    q = {}
    if tier:
        q["tier"] = tier
    if category:
        q["category"] = category
    docs = list(get_collection("dependency_systems").find(q, {"_id": 0}).sort("system_id", 1))
    return docs


def get_system(system_id):
    return get_collection("dependency_systems").find_one({"system_id": system_id}, {"_id": 0})


def create_system(doc, created_by="admin"):
    col = get_collection("dependency_systems")
    sid = (doc.get("system_id") or "").strip()
    if not sid:
        raise ValueError("system_id 必填")
    if col.find_one({"system_id": sid}):
        raise ValueError(f"system_id '{sid}' 已存在")
    now = datetime.utcnow()
    payload = {
        "system_id": sid,
        "display_name": doc.get("display_name") or sid,
        "tier": (doc.get("tier") or "C").upper(),
        "category": doc.get("category") or "AP",
        "description": doc.get("description") or "",
        "owner": doc.get("owner") or "",
        "ap_owner_email": doc.get("ap_owner_email") or "",
        "host_refs": doc.get("host_refs") or [],
        "external": bool(doc.get("external", False)),
        "metadata": doc.get("metadata") or {},
        "created_at": now,
        "updated_at": now,
        "created_by": created_by,
    }
    col.insert_one(payload)
    payload.pop("_id", None)
    return payload


def update_system(system_id, updates, updated_by="admin"):
    col = get_collection("dependency_systems")
    if not col.find_one({"system_id": system_id}):
        return None
    allowed = {"display_name", "tier", "category", "description", "owner",
               "ap_owner_email", "host_refs", "external", "metadata"}
    payload = {k: v for k, v in updates.items() if k in allowed}
    if "tier" in payload:
        payload["tier"] = (payload["tier"] or "C").upper()
    payload["updated_at"] = datetime.utcnow()
    payload["updated_by"] = updated_by
    col.update_one({"system_id": system_id}, {"$set": payload})
    return get_system(system_id)


def delete_system(system_id):
    """刪除系統節點時 cascade 刪除相關邊"""
    sys_col = get_collection("dependency_systems")
    rel_col = get_collection("dependency_relations")
    res = sys_col.delete_one({"system_id": system_id})
    cascade = rel_col.delete_many({"$or": [{"from_system": system_id}, {"to_system": system_id}]})
    return {"deleted_system": res.deleted_count, "cascade_relations": cascade.deleted_count}


# --------------------------------------------------------------------
# 邊 CRUD
# --------------------------------------------------------------------
def list_relations(from_system=None, to_system=None, source=None):
    q = {}
    if from_system:
        q["from_system"] = from_system
    if to_system:
        q["to_system"] = to_system
    if source:
        q["source"] = source
    docs = list(get_collection("dependency_relations").find(q))
    for d in docs:
        d["_id"] = str(d["_id"])
    return docs


def create_relation(doc, created_by="admin"):
    col = get_collection("dependency_relations")
    fs = (doc.get("from_system") or "").strip()
    ts = (doc.get("to_system") or "").strip()
    if not fs or not ts:
        raise ValueError("from_system 與 to_system 必填")
    if fs == ts:
        raise ValueError("不能連自己")
    port = int(doc.get("port") or 0)
    if col.find_one({"from_system": fs, "to_system": ts, "port": port}):
        raise ValueError("此邊已存在 (from/to/port 三欄相同)")
    now = datetime.utcnow()
    payload = {
        "from_system": fs,
        "to_system": ts,
        "relation_type": doc.get("relation_type") or "unknown",
        "protocol": doc.get("protocol") or "TCP",
        "port": port,
        "source": doc.get("source") or "manual",
        "evidence": doc.get("evidence") or {},
        "description": doc.get("description") or "",
        "manual_confirmed": bool(doc.get("manual_confirmed", True)),
        "created_at": now,
        "updated_at": now,
        "created_by": created_by,
    }
    res = col.insert_one(payload)
    payload["_id"] = str(res.inserted_id)
    return payload


def update_relation(rel_id, updates, updated_by="admin"):
    col = get_collection("dependency_relations")
    try:
        oid = ObjectId(rel_id)
    except Exception:
        return None
    if not col.find_one({"_id": oid}):
        return None
    allowed = {"relation_type", "protocol", "port", "description",
               "manual_confirmed", "source", "evidence"}
    payload = {k: v for k, v in updates.items() if k in allowed}
    if "port" in payload:
        payload["port"] = int(payload["port"] or 0)
    payload["updated_at"] = datetime.utcnow()
    payload["updated_by"] = updated_by
    col.update_one({"_id": oid}, {"$set": payload})
    doc = col.find_one({"_id": oid})
    if doc:
        doc["_id"] = str(doc["_id"])
    return doc


def delete_relation(rel_id):
    col = get_collection("dependency_relations")
    try:
        oid = ObjectId(rel_id)
    except Exception:
        return 0
    return col.delete_one({"_id": oid}).deleted_count


# --------------------------------------------------------------------
# 拓撲查詢: 多視圖 (system / host / ip)
# --------------------------------------------------------------------
def topology(center=None, depth=2, limit=200, view="system"):
    """拓撲圖入口 - view=system|host|ip 切換不同節點型態
    v3.16.0.0+: system view 改為從 hosts collection 派生 (主機 = 節點),
    舊式從 dependency_systems 派生改名 view='legacy_system'。
    """
    if view == "host":
        return _topology_host(center=center, limit=limit)
    if view == "ip":
        return _topology_ip(center=center, limit=limit)
    if view == "legacy_system":
        return _topology_system(center=center, depth=depth, limit=limit)
    return _topology_from_hosts(center=center, limit=limit)


def _topology_system(center=None, depth=2, limit=200):
    """
    回傳 {nodes:[...], edges:[...], meta:{...}} 給 vis-network 用。
    - center 不指定：回所有節點 + 所有邊 (節點數超過 limit 截斷)
    - center 指定：BFS 取上下游 depth 層子圖
    """
    sys_col = get_collection("dependency_systems")
    rel_col = get_collection("dependency_relations")

    truncated = False
    if center:
        # BFS: 把 center 同時往 from / to 雙向擴展 depth 層
        seen = {center}
        frontier = {center}
        for _ in range(max(0, depth)):
            if not frontier:
                break
            nxt = set()
            cursor = rel_col.find({"$or": [
                {"from_system": {"$in": list(frontier)}},
                {"to_system": {"$in": list(frontier)}},
            ]}, {"from_system": 1, "to_system": 1})
            for r in cursor:
                if r["from_system"] not in seen:
                    nxt.add(r["from_system"])
                if r["to_system"] not in seen:
                    nxt.add(r["to_system"])
            seen |= nxt
            frontier = nxt
            if len(seen) >= limit:
                truncated = True
                break
        node_ids = list(seen)[:limit]
    else:
        node_ids = [d["system_id"] for d in sys_col.find({}, {"_id": 0, "system_id": 1}).limit(limit)]
        if sys_col.estimated_document_count() > limit:
            truncated = True

    node_set = set(node_ids)
    nodes = list(sys_col.find({"system_id": {"$in": node_ids}}, {"_id": 0}))

    # 補 hosts 在 dependency_systems 之外但出現在 host_refs 的: 不處理 (system 維度才畫)
    # 補 UNKNOWN-* 節點 (採集時找不到對應 system 的)
    unknown_ids = set()
    rel_cursor = rel_col.find({"$or": [
        {"from_system": {"$in": node_ids}},
        {"to_system": {"$in": node_ids}},
    ]})
    edges = []
    for r in rel_cursor:
        fs, ts = r["from_system"], r["to_system"]
        if fs not in node_set and fs.startswith("UNKNOWN-"):
            unknown_ids.add(fs)
        if ts not in node_set and ts.startswith("UNKNOWN-"):
            unknown_ids.add(ts)
        # 兩端至少一端要在子圖內
        if fs in node_set or ts in node_set or fs in unknown_ids or ts in unknown_ids:
            edges.append({
                "id": str(r["_id"]),
                "from": fs,
                "to": ts,
                "relation_type": r.get("relation_type"),
                "protocol": r.get("protocol"),
                "port": r.get("port"),
                "source": r.get("source"),
                "manual_confirmed": r.get("manual_confirmed", True),
                "description": r.get("description", ""),
            })

    # 為 UNKNOWN-* 補虛擬節點 (UI 顯示橘色待確認)
    for uid in unknown_ids:
        nodes.append({
            "system_id": uid,
            "display_name": uid.replace("UNKNOWN-", "未知 "),
            "tier": "C",
            "category": "External",
            "external": True,
            "_unknown": True,
        })

    return {
        "nodes": nodes,
        "edges": edges,
        "meta": {
            "node_count": len(nodes),
            "edge_count": len(edges),
            "truncated": truncated,
            "center": center,
            "depth": depth,
            "limit": limit,
            "view": "system",
        },
    }


# --------------------------------------------------------------------
# 主機視圖: 把 system 攤平成 hostname 節點, 邊用 (caller_host, target_system 內某 host) cross-product
# --------------------------------------------------------------------
def _topology_host(center=None, limit=200):
    sys_col = get_collection("dependency_systems")
    rel_col = get_collection("dependency_relations")
    hosts_col = get_collection("hosts")

    systems = list(sys_col.find({}, {"_id": 0}))
    sys_map = {s["system_id"]: s for s in systems}
    hosts_meta = {h["hostname"]: h for h in hosts_col.find({}, {"_id": 0})}

    # 節點: 每個 system 的 host_refs 攤開 + UNKNOWN-<ip> system (用 system_id 當 hostname,因為沒主機)
    nodes = []
    seen_hosts = set()
    for s in systems:
        sid = s["system_id"]
        tier = (s.get("tier") or "C").upper()
        if not s.get("host_refs"):
            # 外部/未知系統: 用 system_id 當虛擬 hostname
            label = s.get("display_name") or sid
            if sid not in seen_hosts:
                seen_hosts.add(sid)
                meta = hosts_meta.get(sid, {})
                nodes.append({
                    "id": sid,
                    "hostname": sid,
                    "ip": meta.get("ip") or s.get("metadata", {}).get("ip", ""),
                    "os": meta.get("os") or "(外部)",
                    "system_id": sid,
                    "system_name": label,
                    "tier": tier,
                    "category": s.get("category"),
                    "_unknown": s.get("external", False) or sid.startswith("UNKNOWN-") or sid.startswith("EXT-"),
                })
            continue
        for h in s["host_refs"]:
            if h in seen_hosts:
                continue
            seen_hosts.add(h)
            meta = hosts_meta.get(h, {})
            nodes.append({
                "id": h,
                "hostname": h,
                "ip": meta.get("ip", ""),
                "os": meta.get("os", ""),
                "system_id": sid,
                "system_name": s.get("display_name") or sid,
                "tier": tier,
                "category": s.get("category"),
            })

    # 邊: 對每條 dependency_relations, cross-product 來源 system 的 hosts × 目標 system 的 hosts
    # 簡化: 1 條 system 邊 → 取 caller system 第一台 host + target system 第一台 host (或 system_id 如無)
    # 並把 evidence.sample_hosts 的真實連線優先採用
    edges = []
    rel_docs = list(rel_col.find({}))
    for r in rel_docs:
        fs, ts = r["from_system"], r["to_system"]
        s_from = sys_map.get(fs)
        s_to = sys_map.get(ts)
        if not s_from or not s_to:
            continue

        # 來源 host: 優先用 evidence.sample_hosts (真實採集), 否則第一台 host_refs, 否則 system_id
        src_hosts = r.get("evidence", {}).get("sample_hosts") or s_from.get("host_refs") or [fs]
        # 目標 host: 用第一台 host_refs, 否則 system_id (UNKNOWN/EXT)
        tgt_hosts = s_to.get("host_refs") or [ts]

        for src_h in src_hosts:
            for tgt_h in tgt_hosts:
                if src_h == tgt_h:
                    continue
                edges.append({
                    "id": f"{r['_id']}__{src_h}__{tgt_h}",
                    "from": src_h,
                    "to": tgt_h,
                    "relation_type": r.get("relation_type"),
                    "protocol": r.get("protocol"),
                    "port": r.get("port"),
                    "source": r.get("source"),
                    "manual_confirmed": r.get("manual_confirmed", True),
                    "process": r.get("evidence", {}).get("last_process", ""),
                    "description": r.get("description", ""),
                })

    # center filter (BFS limit hosts)
    if center:
        keep = {center}
        frontier = {center}
        adj = {}
        for e in edges:
            adj.setdefault(e["from"], set()).add(e["to"])
            adj.setdefault(e["to"], set()).add(e["from"])
        for _ in range(2):
            nxt = set()
            for h in frontier:
                nxt |= adj.get(h, set())
            keep |= nxt
            frontier = nxt - keep
        nodes = [n for n in nodes if n["id"] in keep]
        edges = [e for e in edges if e["from"] in keep or e["to"] in keep]

    if len(nodes) > limit:
        nodes = nodes[:limit]
        keep_ids = {n["id"] for n in nodes}
        edges = [e for e in edges if e["from"] in keep_ids and e["to"] in keep_ids]
        truncated = True
    else:
        truncated = False

    return {
        "nodes": nodes,
        "edges": edges,
        "meta": {
            "node_count": len(nodes),
            "edge_count": len(edges),
            "truncated": truncated,
            "center": center,
            "limit": limit,
            "view": "host",
        },
    }


# --------------------------------------------------------------------
# IP 視圖: 節點 = hosts.ip + UNKNOWN/EXT 系統的 IP, 邊用採集到的 last_remote_ip
# --------------------------------------------------------------------
def _topology_ip(center=None, limit=200):
    sys_col = get_collection("dependency_systems")
    rel_col = get_collection("dependency_relations")
    hosts_col = get_collection("hosts")

    hosts_meta = {h["hostname"]: h for h in hosts_col.find({}, {"_id": 0})}
    hostname_to_ip = {h: meta.get("ip") for h, meta in hosts_meta.items() if meta.get("ip")}
    ip_to_hostname = {v: k for k, v in hostname_to_ip.items()}

    nodes = []
    seen_ips = set()

    # 從 hosts collection 撐節點
    for h, meta in hosts_meta.items():
        ip = meta.get("ip")
        if not ip or ip in seen_ips:
            continue
        seen_ips.add(ip)
        nodes.append({
            "id": ip,
            "ip": ip,
            "hostname": h,
            "os": meta.get("os", ""),
            "system_id": "",
            "tier": "C",
            "label_extra": h,
        })

    # 從 dependency_relations.evidence.last_remote_ip 撐節點 (採集才看到的外部 IP)
    for r in rel_col.find({"source": "ss-tunp"}, {"evidence.last_remote_ip": 1, "to_system": 1}):
        rip = r.get("evidence", {}).get("last_remote_ip")
        if rip and rip not in seen_ips:
            seen_ips.add(rip)
            ts = r.get("to_system", "")
            nodes.append({
                "id": rip,
                "ip": rip,
                "hostname": ip_to_hostname.get(rip, ""),
                "system_id": ts,
                "tier": "C",
                "_unknown": ts.startswith("UNKNOWN-") or ts.startswith("EXT-"),
                "label_extra": ts if (ts.startswith("EXT-") or ts.startswith("UNKNOWN-")) else "",
            })

    # 補 UNKNOWN/EXT 系統的 metadata.ip 或 cidr 當虛擬節點
    for s in sys_col.find({"external": True}, {"_id": 0}):
        meta_ip = s.get("metadata", {}).get("ip")
        if meta_ip and meta_ip not in seen_ips:
            seen_ips.add(meta_ip)
            nodes.append({
                "id": meta_ip,
                "ip": meta_ip,
                "system_id": s["system_id"],
                "tier": (s.get("tier") or "C").upper(),
                "_unknown": True,
                "label_extra": s.get("display_name") or s["system_id"],
            })

    # 邊: 用 evidence.sample_hosts (caller hostname → IP) → last_remote_ip (target IP)
    edges = []
    for r in rel_col.find({}):
        rip_target = r.get("evidence", {}).get("last_remote_ip")
        sample_hosts = r.get("evidence", {}).get("sample_hosts") or []
        port = r.get("port")
        proto = r.get("protocol", "TCP")
        source = r.get("source", "manual")

        # IP-IP 邊只有採集出來的才精準, manual 沒 evidence 就用 system 內第一台 host 的 IP
        target_ips = []
        if rip_target:
            target_ips = [rip_target]
        else:
            ts = r["to_system"]
            for s in [d for d in sys_col.find({"system_id": ts}, {"host_refs": 1, "metadata": 1, "_id": 0})]:
                for h in s.get("host_refs", []) or []:
                    if h in hostname_to_ip:
                        target_ips.append(hostname_to_ip[h])
                if not target_ips and s.get("metadata", {}).get("ip"):
                    target_ips.append(s["metadata"]["ip"])

        if not target_ips:
            continue

        # caller IPs
        caller_ips = []
        for h in sample_hosts:
            if h in hostname_to_ip:
                caller_ips.append(hostname_to_ip[h])
        if not caller_ips:
            fs = r["from_system"]
            for s in [d for d in sys_col.find({"system_id": fs}, {"host_refs": 1, "_id": 0})]:
                for h in s.get("host_refs", []) or []:
                    if h in hostname_to_ip:
                        caller_ips.append(hostname_to_ip[h])

        for cip in caller_ips:
            for tip in target_ips:
                if cip == tip:
                    continue
                edges.append({
                    "id": f"{r['_id']}__{cip}__{tip}",
                    "from": cip,
                    "to": tip,
                    "port": port,
                    "protocol": proto,
                    "source": source,
                    "manual_confirmed": r.get("manual_confirmed", True),
                    "process": r.get("evidence", {}).get("last_process", ""),
                })

    if len(nodes) > limit:
        nodes = nodes[:limit]
        keep = {n["id"] for n in nodes}
        edges = [e for e in edges if e["from"] in keep and e["to"] in keep]
        truncated = True
    else:
        truncated = False

    return {
        "nodes": nodes,
        "edges": edges,
        "meta": {
            "node_count": len(nodes),
            "edge_count": len(edges),
            "truncated": truncated,
            "center": center,
            "limit": limit,
            "view": "ip",
        },
    }


# --------------------------------------------------------------------
# 採集排程 (cron) - 寫 sysinfra 自己的 user crontab
# --------------------------------------------------------------------
import subprocess
import os as _os

CRON_MARKER = "# ITAGENT_DEP_COLLECT"


def _read_user_crontab():
    """讀當前使用者 (gunicorn = sysinfra) 的 crontab,沒有就空字串"""
    try:
        r = subprocess.run(["crontab", "-l"], capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            return r.stdout
        # rc != 0 通常是 "no crontab for user", 視為空
        return ""
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return ""


def _write_user_crontab(content):
    """寫 crontab,內容若空就 remove"""
    if not content.strip():
        # 清空: crontab -r
        subprocess.run(["crontab", "-r"], capture_output=True, text=True, timeout=5)
        return True
    r = subprocess.run(["crontab", "-"], input=content, text=True, capture_output=True, timeout=5)
    return r.returncode == 0


def get_collect_schedule():
    """
    回 dict:
      {
        enabled: bool,
        interval_min: int (5/10/15/30/60/0=disabled),
        business_hours_only: bool,
        cron_line: str (raw, 給 UI 顯示),
        last_run_at: ISO str | None,
      }
    """
    raw = _read_user_crontab()
    enabled = False
    interval_min = 0
    business_hours_only = True
    cron_line = ""
    for line in raw.split("\n"):
        if CRON_MARKER in line:
            enabled = True
            cron_line = line.strip()
            # 解析 time spec: "*/N H1-H2 * * D1-D2 ..."
            parts = line.strip().split()
            if len(parts) >= 5:
                minute_part = parts[0]
                hour_part = parts[1]
                dow_part = parts[4]
                if minute_part.startswith("*/"):
                    try:
                        interval_min = int(minute_part[2:])
                    except ValueError:
                        interval_min = 0
                # 上班時間: hour 是 9-18 / 8-19 等範圍, dow 是 1-5
                business_hours_only = ("-" in hour_part or hour_part != "*") and ("-" in dow_part or dow_part not in ("*",))
            break

    # 抓最後一次跑的時間 (從 dependency_collect_runs)
    last_run_at = None
    try:
        last = get_collection("dependency_collect_runs").find_one(
            {}, sort=[("started_at", -1)]
        )
        if last and last.get("started_at"):
            last_run_at = last["started_at"].isoformat() if hasattr(last["started_at"], "isoformat") else last["started_at"]
    except Exception:
        pass

    return {
        "enabled": enabled,
        "interval_min": interval_min,
        "business_hours_only": business_hours_only,
        "cron_line": cron_line,
        "last_run_at": last_run_at,
    }


def set_collect_schedule(interval_min, business_hours_only=True, limit_hosts=None):
    """
    寫/改/刪 sysinfra crontab 的 dep_collect 行
    interval_min = 0 視為關閉 (移除既有行)

    Returns: {success, message, cron_line}
    """
    interval_min = int(interval_min or 0)
    if interval_min not in (0, 5, 10, 15, 30, 60):
        raise ValueError("interval_min 必須是 0/5/10/15/30/60")

    raw = _read_user_crontab()
    # 移除既有 marker 行
    new_lines = [l for l in raw.split("\n") if CRON_MARKER not in l]
    # 去尾空行
    while new_lines and not new_lines[-1].strip():
        new_lines.pop()

    cron_line = ""
    if interval_min > 0:
        if business_hours_only:
            time_spec = f"*/{interval_min} 9-18 * * 1-5"
        else:
            time_spec = f"*/{interval_min} * * * *"
        # 找 INSPECTION_HOME (不能 hardcode,要 auto-detect)
        ihome = _os.environ.get("INSPECTION_HOME", "")
        if not ihome:
            for cand in ("/seclog/AI/inspection", "/opt/inspection"):
                if _os.path.isfile(_os.path.join(cand, "data", "version.json")):
                    ihome = cand
                    break
        if not ihome:
            ihome = "/opt/inspection"  # fallback
        script = f"{ihome}/scripts/run_dep_collect.sh"
        env_extra = ""
        if limit_hosts:
            env_extra = f"DEP_COLLECT_LIMIT='{limit_hosts}' "
        cron_line = f"{time_spec} {env_extra}{script} {CRON_MARKER}"
        new_lines.append(cron_line)

    new_content = "\n".join(new_lines) + "\n"
    ok = _write_user_crontab(new_content)
    return {
        "success": ok,
        "message": "已套用採集排程" if interval_min > 0 else "已停用採集排程",
        "cron_line": cron_line,
        "interval_min": interval_min,
        "business_hours_only": business_hours_only,
    }


# --------------------------------------------------------------------
# Ghost 分析: 揪出連線對端不在 hosts collection 也不是已知外部的 IP
# --------------------------------------------------------------------
def analyze_ghosts():
    """
    從 dependency_relations 拿所有 evidence.last_remote_ip,
    扣掉 hosts.ip + KNOWN_EXTERNAL 已分類的, 剩下的就是 ghost (未納管 / 不明對端).

    分類:
      - private_unmanaged: 內網段 IP 但不在 hosts 內 (最可疑, shadow IT)
      - public_unknown:    外網 IP 但不在 KNOWN_EXTERNAL 清單 (可能是雲服務 / 外部 API)

    回 list, 按 seen_count desc 排序, 高活動 ghost 在最上面
    """
    import ipaddress

    hosts_col = get_collection("hosts")
    sys_col = get_collection("dependency_systems")
    rel_col = get_collection("dependency_relations")

    known_host_ips = set()
    for h in hosts_col.find({}, {"_id": 0, "hostname": 1, "ip": 1}):
        if h.get("ip"):
            known_host_ips.add(h["ip"])

    # KNOWN_EXTERNAL 也要 exclude (cloudflared 連 cloudflare CDN 不算 ghost)
    # 走 dependency_systems.metadata.cidr 累積 (seed_collect.py 註冊的 EXT-CLOUDFLARE 等)
    known_external_cidrs = []
    known_external_label = {}  # cidr_str -> system display_name
    for s in sys_col.find({"external": True}, {"_id": 0, "system_id": 1, "display_name": 1, "metadata": 1}):
        cidr = (s.get("metadata") or {}).get("cidr")
        if cidr:
            try:
                known_external_cidrs.append((ipaddress.ip_network(cidr), s["system_id"], s.get("display_name", "")))
            except (ValueError, TypeError):
                pass

    def _classify_ext(ip_addr):
        """已知外部段?"""
        for net, sid, label in known_external_cidrs:
            if ip_addr in net:
                return sid, label
        return None

    def _is_private(ip_addr):
        return ip_addr.is_private and not ip_addr.is_loopback and not ip_addr.is_link_local

    ghosts = {}  # ip -> aggregated info
    for r in rel_col.find({}):
        ev = r.get("evidence") or {}
        rip = ev.get("last_remote_ip")
        if not rip:
            continue
        if rip in known_host_ips:
            continue  # 已納管,跳

        try:
            ip_addr = ipaddress.ip_address(rip)
        except ValueError:
            continue
        if ip_addr.is_loopback:
            continue

        ext = _classify_ext(ip_addr)
        if ext:
            # 已分類為已知外部,雖然不在 hosts 但有歸屬,跳
            continue

        if _is_private(ip_addr):
            classification = "private_unmanaged"
            severity = "high"
        elif ip_addr.is_global:
            classification = "public_unknown"
            severity = "medium"
        else:
            classification = "other"
            severity = "low"

        if rip not in ghosts:
            ghosts[rip] = {
                "ip": rip,
                "classification": classification,
                "severity": severity,
                "to_system": r.get("to_system"),  # 可能是 UNKNOWN-<ip>
                "callers": set(),
                "ports": set(),
                "processes": set(),
                "first_seen": ev.get("first_seen_at"),
                "last_seen": ev.get("last_seen_at"),
                "seen_count": 0,
                "edge_ids": [],
            }
        g = ghosts[rip]
        g["seen_count"] += int(ev.get("seen_count", 1))
        for h in ev.get("sample_hosts", []) or []:
            g["callers"].add(h)
        if r.get("port"):
            g["ports"].add(int(r["port"]))
        if ev.get("last_process"):
            g["processes"].add(ev["last_process"])
        g["edge_ids"].append(str(r.get("_id", "")))
        # 收最早 first_seen / 最晚 last_seen
        fs = ev.get("first_seen_at")
        ls = ev.get("last_seen_at")
        if fs and (g["first_seen"] is None or fs < g["first_seen"]):
            g["first_seen"] = fs
        if ls and (g["last_seen"] is None or ls > g["last_seen"]):
            g["last_seen"] = ls

    # set -> list, datetime -> isoformat (jsonify 不認 set)
    out = []
    for g in ghosts.values():
        out.append({
            "ip": g["ip"],
            "classification": g["classification"],
            "severity": g["severity"],
            "to_system": g["to_system"],
            "callers": sorted(g["callers"]),
            "ports": sorted(g["ports"]),
            "processes": sorted(g["processes"]),
            "first_seen": g["first_seen"].isoformat() if hasattr(g["first_seen"], "isoformat") else g["first_seen"],
            "last_seen": g["last_seen"].isoformat() if hasattr(g["last_seen"], "isoformat") else g["last_seen"],
            "seen_count": g["seen_count"],
            "edge_ids": g["edge_ids"],
        })

    # 排序: severity high → medium → low,內同 seen_count desc
    sev_order = {"high": 0, "medium": 1, "low": 2}
    out.sort(key=lambda x: (sev_order.get(x["severity"], 9), -x["seen_count"], x["ip"]))
    return out


def adopt_ghost(ip, action, payload=None):
    """處理 ghost: 'add_host' / 'mark_external' / 'ignore'

    add_host: 把 IP 加進 hosts collection (UI 後續可繼續補 hostname/owner 等)
    mark_external: 建/合併 EXT-* 系統節點 (永久排除 ghost 列表)
    ignore: 在 settings collection 寫白名單 (暫時)
    """
    payload = payload or {}
    if action == "add_host":
        hosts_col = get_collection("hosts")
        hostname = (payload.get("hostname") or f"unmanaged-{ip.replace('.','-')}").strip()
        if hosts_col.find_one({"hostname": hostname}):
            raise ValueError(f"hostname '{hostname}' 已存在")
        if hosts_col.find_one({"ip": ip}):
            raise ValueError(f"IP '{ip}' 已存在於 hosts")
        hosts_col.insert_one({
            "hostname": hostname,
            "ip": ip,
            "os": payload.get("os", ""),
            "system_name": payload.get("system_name", ""),
            "tier": payload.get("tier", "C"),
            "owner": payload.get("owner", ""),
            "custodian": payload.get("custodian", ""),
            "department": payload.get("department", ""),
            "created_at": datetime.utcnow(),
            "created_by": "ghost_adopt",
            "_adopted_from_ghost": True,
        })
        return {"action": "add_host", "hostname": hostname, "ip": ip}

    if action == "mark_external":
        sys_col = get_collection("dependency_systems")
        sid = (payload.get("system_id") or f"EXT-{ip.replace('.','-')}").upper()
        if sys_col.find_one({"system_id": sid}):
            raise ValueError(f"system_id '{sid}' 已存在")
        cidr = payload.get("cidr") or f"{ip}/32"
        sys_col.insert_one({
            "system_id": sid,
            "display_name": payload.get("display_name") or f"外部 {ip}",
            "tier": "C",
            "category": "External",
            "owner": payload.get("owner", "(已標記)"),
            "host_refs": [],
            "external": True,
            "description": payload.get("description") or f"從 ghost 升級為已知外部 {ip}",
            "metadata": {"auto_added": True, "cidr": cidr, "from_ghost": True},
            "created_at": datetime.utcnow(),
            "updated_at": datetime.utcnow(),
            "created_by": "ghost_adopt",
        })
        # 同時把 dependency_relations 內 to_system=UNKNOWN-<ip> 的改指過來
        rel_col = get_collection("dependency_relations")
        old_sid = f"UNKNOWN-{ip}"
        rel_col.update_many({"to_system": old_sid}, {"$set": {"to_system": sid, "manual_confirmed": True}})
        # 刪舊 UNKNOWN-<ip> 系統節點
        sys_col.delete_one({"system_id": old_sid})
        return {"action": "mark_external", "system_id": sid, "cidr": cidr}

    if action == "ignore":
        # 寫進 settings collection 的 ghost_ignore_list
        from services.mongo_service import get_collection as _gc
        _gc("settings").update_one(
            {"key": "dependency_ghost_ignore"},
            {"$addToSet": {"value": ip}},
            upsert=True,
        )
        return {"action": "ignore", "ip": ip}

    raise ValueError(f"未知 action: {action}")


# --------------------------------------------------------------------
# 影響分析 ($graphLookup) — Stage 2 主用，Stage 1 先預留
# --------------------------------------------------------------------
def downstream_impact(system_id, max_depth=3):
    """
    從 system_id 出發找下游受影響的系統 (caller 故障 → 沿 from→to 繼續找)。
    回傳: [{system_id, level, path}]
    """
    rel_col = get_collection("dependency_relations")
    pipeline = [
        {"$match": {"from_system": system_id}},
        {"$graphLookup": {
            "from": "dependency_relations",
            "startWith": "$to_system",
            "connectFromField": "to_system",
            "connectToField": "from_system",
            "as": "downstream",
            "maxDepth": max(0, int(max_depth) - 1),
            "depthField": "level",
        }},
    ]
    affected = {}
    for doc in rel_col.aggregate(pipeline):
        ts = doc["to_system"]
        affected.setdefault(ts, 0)
        for sub in doc.get("downstream", []):
            sid = sub["to_system"]
            lvl = int(sub.get("level", 0)) + 1
            if sid not in affected or lvl < affected[sid]:
                affected[sid] = lvl
    return [{"system_id": k, "level": v} for k, v in sorted(affected.items(), key=lambda x: (x[1], x[0]))]


def upstream_impact(system_id, max_depth=3):
    """
    反向: 誰會因為 system_id 故障而受影響 (這是 caller 那側)。
    從 to_system=X 倒查 from_system 們。
    """
    rel_col = get_collection("dependency_relations")
    pipeline = [
        {"$match": {"to_system": system_id}},
        {"$graphLookup": {
            "from": "dependency_relations",
            "startWith": "$from_system",
            "connectFromField": "from_system",
            "connectToField": "to_system",
            "as": "upstream",
            "maxDepth": max(0, int(max_depth) - 1),
            "depthField": "level",
        }},
    ]
    affected = {}
    for doc in rel_col.aggregate(pipeline):
        fs = doc["from_system"]
        affected.setdefault(fs, 0)
        for sub in doc.get("upstream", []):
            sid = sub["from_system"]
            lvl = int(sub.get("level", 0)) + 1
            if sid not in affected or lvl < affected[sid]:
                affected[sid] = lvl
    return [{"system_id": k, "level": v} for k, v in sorted(affected.items(), key=lambda x: (x[1], x[0]))]


def _tier_to_letter(t):
    """金/銀/銅 → A/B/C (跟舊 system tier 字母對齊)"""
    return {"金":"A","銀":"B","銅":"C"}.get(str(t).strip(), "C")


def _topology_from_hosts(center=None, limit=200):
    """v3.16.0.0+: 拓撲節點從 hosts collection 直接派生.
    每台主機 = 一個節點 (system_id = hostname).
    外部節點: dependency_systems 內 host_refs 為空 (AD/DNS/EXT-*/UNKNOWN-*)。
    """
    hosts_col = get_collection("hosts")
    sys_col = get_collection("dependency_systems")
    rel_col = get_collection("dependency_relations")

    nodes = []
    seen_ids = set()

    # 內部節點: 每台 host 一個 node, system_id = hostname
    for h in hosts_col.find({}, {"_id": 0}):
        hn = h.get("hostname")
        if not hn or hn in seen_ids:
            continue
        seen_ids.add(hn)
        nodes.append({
            "system_id": hn,
            "display_name": h.get("system_name") or h.get("apid") or hn,
            "tier": _tier_to_letter(h.get("tier", "")),
            "category": h.get("group_name") or "Internal",
            "host_refs": [hn],
            "hostname": hn,
            "ip": (h.get("ips") or [h.get("ip", "")])[0] if (h.get("ips") or h.get("ip")) else "",
            "owner": h.get("owner", "") or h.get("custodian", ""),
            "description": h.get("note", "") or f"{h.get('os','')} / {h.get('device_model','')}",
            "_internal": True,
            "asset_seq": h.get("asset_seq", ""),
            "custodian": h.get("custodian", ""),
        })

    # 外部節點: dependency_systems 內 host_refs 為空 (純外部)
    for ext in sys_col.find({}, {"_id": 0}):
        sid = ext.get("system_id")
        if not sid or sid in seen_ids:
            continue
        host_refs = ext.get("host_refs") or []
        # 內部 (有 host_refs) 跳過 — 已用 hosts 派生過
        if host_refs:
            continue
        seen_ids.add(sid)
        nodes.append({
            "system_id": sid,
            "display_name": ext.get("display_name") or sid,
            "tier": ext.get("tier", "C"),
            "category": ext.get("category", "External"),
            "host_refs": [],
            "owner": ext.get("owner", ""),
            "description": ext.get("description", ""),
            "_external": True,
            "_unknown": sid.startswith("UNKNOWN-"),
        })

    # 邊: 過濾出兩端都在節點清單內的
    valid_ids = {n["system_id"] for n in nodes}
    edges = []
    for r in rel_col.find({}):
        if r.get("from_system") in valid_ids and r.get("to_system") in valid_ids:
            edges.append({
                "id": str(r.get("_id")) if r.get("_id") else "e_" + str(r.get("from_system","")) + "_" + str(r.get("to_system","")) + "_" + str(r.get("port",0)),
                "from": r["from_system"],
                "to": r["to_system"],
                "relation_type": r.get("relation_type", "network"),
                "port": r.get("port"),
                "protocol": r.get("protocol", ""),
                "source": r.get("source", "manual"),
                "manual_confirmed": r.get("manual_confirmed", True),
                "description": r.get("description", ""),
            })

    truncated = len(nodes) > limit
    return {
        "nodes": nodes[:limit],
        "edges": edges,
        "meta": {
            "node_count": len(nodes),
            "edge_count": len(edges),
            "truncated": truncated,
            "view": "hosts-derived",
        },
    }

