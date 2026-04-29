"""系統聯通圖 API"""
import os
import sys
import shlex
import subprocess
from datetime import datetime
from flask import Blueprint, request, jsonify, render_template, session

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from decorators import login_required, admin_required
from services import dependency_service
from services.mongo_service import get_collection

bp = Blueprint("api_dependencies", __name__)

INSPECTION_HOME = os.environ.get("INSPECTION_HOME", "/opt/inspection")
ANSIBLE_DIR = os.path.join(INSPECTION_HOME, "ansible")
SCRIPTS_DIR = os.path.join(INSPECTION_HOME, "scripts")
LOGS_DIR = os.path.join(INSPECTION_HOME, "logs")


# ====================================================================
# 頁面
# ====================================================================
@bp.route("/dependencies", methods=["GET"])
@login_required
def page():
    return render_template("dependencies.html")


@bp.route("/dependencies/fullscreen", methods=["GET"])
@login_required
def page_fullscreen():
    """全螢幕拓撲圖 - 給 vis-network 互動體驗用 (新分頁開)"""
    return render_template("dependencies_fullscreen.html")


@bp.route("/dependencies/ghosts", methods=["GET"])
@login_required
def page_ghosts():
    """Ghost 分析頁 - 列出採集到但不在 hosts collection 的對端 IP"""
    return render_template("dependencies_ghosts.html")


@bp.route("/api/dependencies/ghosts", methods=["GET"])
@login_required
def list_ghosts():
    """揪出未納管對端 IP (內網不在 hosts + 外網不在 KNOWN_EXTERNAL)"""
    data = dependency_service.analyze_ghosts()
    high = sum(1 for g in data if g["severity"] == "high")
    medium = sum(1 for g in data if g["severity"] == "medium")
    return jsonify({
        "success": True,
        "data": data,
        "count": len(data),
        "summary": {"high": high, "medium": medium, "total": len(data)},
    })


@bp.route("/api/dependencies/ghosts/<ip>/adopt", methods=["POST"])
@admin_required
def adopt_ghost(ip):
    """處理 ghost: action=add_host|mark_external|ignore"""
    body = request.get_json(silent=True) or {}
    action = body.get("action")
    if not action:
        return jsonify({"success": False, "error": "action 必填", "code": 400}), 400
    try:
        result = dependency_service.adopt_ghost(ip, action, body)
    except ValueError as e:
        return jsonify({"success": False, "error": str(e), "code": 400}), 400
    return jsonify({"success": True, "data": result})


# ====================================================================
# 系統節點 CRUD
# ====================================================================
@bp.route("/api/dependencies/systems", methods=["GET"])
@login_required
def list_systems():
    tier = request.args.get("tier")
    category = request.args.get("category")
    data = dependency_service.list_systems(tier=tier, category=category)
    return jsonify({"success": True, "data": data, "count": len(data)})


@bp.route("/api/dependencies/systems/<system_id>", methods=["GET"])
@login_required
def get_system(system_id):
    doc = dependency_service.get_system(system_id)
    if not doc:
        return jsonify({"success": False, "error": "找不到系統", "code": 404}), 404
    return jsonify({"success": True, "data": doc})


@bp.route("/api/dependencies/systems", methods=["POST"])
@admin_required
def create_system():
    body = request.get_json(silent=True) or {}
    try:
        doc = dependency_service.create_system(body, created_by=session.get("username", "admin"))
    except ValueError as e:
        return jsonify({"success": False, "error": str(e), "code": 400}), 400
    return jsonify({"success": True, "data": doc})


@bp.route("/api/dependencies/systems/<system_id>", methods=["PUT"])
@admin_required
def update_system(system_id):
    body = request.get_json(silent=True) or {}
    doc = dependency_service.update_system(system_id, body, updated_by=session.get("username", "admin"))
    if not doc:
        return jsonify({"success": False, "error": "找不到系統", "code": 404}), 404
    return jsonify({"success": True, "data": doc})


@bp.route("/api/dependencies/systems/<system_id>", methods=["DELETE"])
@admin_required
def delete_system(system_id):
    res = dependency_service.delete_system(system_id)
    if res["deleted_system"] == 0:
        return jsonify({"success": False, "error": "找不到系統", "code": 404}), 404
    return jsonify({"success": True, "data": res})


# ====================================================================
# 邊 CRUD
# ====================================================================
@bp.route("/api/dependencies/relations", methods=["GET"])
@login_required
def list_relations():
    fs = request.args.get("from")
    ts = request.args.get("to")
    src = request.args.get("source")
    data = dependency_service.list_relations(from_system=fs, to_system=ts, source=src)
    return jsonify({"success": True, "data": data, "count": len(data)})


@bp.route("/api/dependencies/relations", methods=["POST"])
@admin_required
def create_relation():
    body = request.get_json(silent=True) or {}
    try:
        doc = dependency_service.create_relation(body, created_by=session.get("username", "admin"))
    except ValueError as e:
        return jsonify({"success": False, "error": str(e), "code": 400}), 400
    return jsonify({"success": True, "data": doc})


@bp.route("/api/dependencies/relations/<rel_id>", methods=["PUT"])
@admin_required
def update_relation(rel_id):
    body = request.get_json(silent=True) or {}
    doc = dependency_service.update_relation(rel_id, body, updated_by=session.get("username", "admin"))
    if not doc:
        return jsonify({"success": False, "error": "找不到該邊", "code": 404}), 404
    return jsonify({"success": True, "data": doc})


@bp.route("/api/dependencies/relations/<rel_id>", methods=["DELETE"])
@admin_required
def delete_relation(rel_id):
    n = dependency_service.delete_relation(rel_id)
    if n == 0:
        return jsonify({"success": False, "error": "找不到該邊", "code": 404}), 404
    return jsonify({"success": True, "deleted": n})


# ====================================================================
# 拓撲查詢 (給 vis-network)
# ====================================================================
@bp.route("/api/dependencies/topology", methods=["GET"])
@login_required
def topology():
    center = request.args.get("center")
    view = (request.args.get("view") or "system").lower()
    if view not in ("system", "host", "ip"):
        view = "system"
    try:
        depth = max(0, min(int(request.args.get("depth", 2)), 6))
        limit = max(10, min(int(request.args.get("limit", 200)), 500))
    except (TypeError, ValueError):
        return jsonify({"success": False, "error": "depth / limit 必須為數字", "code": 400}), 400
    data = dependency_service.topology(center=center, depth=depth, limit=limit, view=view)
    return jsonify({"success": True, "data": data})


# ====================================================================
# 影響分析 (Stage 2 主用，Stage 1 先預留)
# ====================================================================
@bp.route("/api/dependencies/impact", methods=["GET"])
@login_required
def impact():
    system_id = request.args.get("system_id")
    if not system_id:
        return jsonify({"success": False, "error": "system_id 必填", "code": 400}), 400
    try:
        depth = max(1, min(int(request.args.get("depth", 3)), 6))
    except (TypeError, ValueError):
        depth = 3
    affected = dependency_service.downstream_impact(system_id, max_depth=depth)
    return jsonify({
        "success": True,
        "data": {
            "system_id": system_id,
            "depth": depth,
            "affected_systems": affected,
            "count": len(affected),
        },
    })


@bp.route("/api/dependencies/collect/trigger", methods=["POST"])
@admin_required
def collect_trigger():
    """背景執行 ansible-playbook collect_connections.yml + dependency_seed_collect.py

    流程: 1) 在 dependency_collect_runs 寫一筆 status=running
          2) spawn subprocess 跑 playbook + seed,完成後 update status
          3) 立刻回 run_id 給前端輪詢
    """
    body = request.get_json(silent=True) or {}
    limit = (body.get("limit") or "").strip()  # hostname or 'all'

    now = datetime.utcnow()
    run_id = f"dep_{now.strftime('%Y%m%d_%H%M%S')}"
    run_col = get_collection("dependency_collect_runs")
    run_col.insert_one({
        "run_id": run_id,
        "started_at": now,
        "finished_at": None,
        "status": "running",
        "triggered_by": session.get("username", "admin"),
        "limit": limit or "all",
        "edges_added": 0,
        "edges_updated": 0,
        "new_unknowns": [],
    })

    os.makedirs(LOGS_DIR, exist_ok=True)
    logfile = os.path.join(LOGS_DIR, f"dep_collect_{run_id}.log")
    # default 採 inventory 全部 (13 / 221 / 任一環境通用; playbook 內已 skip 非 Linux)
    # 之前寫死 'secansible:secclient1:sec9c2' 在公司環境 inventory 沒這名字 → no hosts to target
    limit_arg = f"--limit {shlex.quote(limit)}" if limit else "--limit all"

    # 兩階段: ansible-playbook → seed_collect (gunicorn 已用 sysinfra 跑,不需 sudo)
    cmd = (
        f"export INSPECTION_HOME={shlex.quote(INSPECTION_HOME)} && "
        f"cd {shlex.quote(ANSIBLE_DIR)} && "
        f"ansible-playbook -i inventory/hosts.yml playbooks/collect_connections.yml "
        f"{limit_arg} -e inspection_home_override={shlex.quote(INSPECTION_HOME)} && "
        f"python3 {shlex.quote(os.path.join(SCRIPTS_DIR, 'dependency_seed_collect.py'))} && "
        f"echo COLLECT_OK"
    )
    full = f"nohup bash -c {shlex.quote(cmd)} > {shlex.quote(logfile)} 2>&1 &"
    try:
        subprocess.Popen(["bash", "-c", full], close_fds=True)
    except Exception as e:
        run_col.update_one(
            {"run_id": run_id},
            {"$set": {"status": "failed", "finished_at": datetime.utcnow(), "error": str(e)}},
        )
        return jsonify({"success": False, "error": f"spawn failed: {e}"}), 500

    return jsonify({
        "success": True,
        "data": {"run_id": run_id, "log": os.path.basename(logfile), "limit": limit or "all"},
    })


@bp.route("/api/dependencies/collect/status/<run_id>", methods=["GET"])
@login_required
def collect_status(run_id):
    """回最新一筆 dependency_collect_runs 的 status (給前端輪詢)

    若 run_id 是 'latest' 回最新一筆;若指定 run_id 但 status 還是 running,
    主動掃 collect_runs 看是否有 dependency_seed_collect.py 寫入的同 epoch 記錄。
    """
    run_col = get_collection("dependency_collect_runs")
    if run_id == "latest":
        doc = run_col.find_one({}, sort=[("started_at", -1)])
    else:
        doc = run_col.find_one({"run_id": run_id})

    if not doc:
        return jsonify({"success": False, "error": "找不到 run_id", "code": 404}), 404

    # 若狀態還是 running,看後續有沒有 seed_collect 寫的同 epoch 記錄 (它另外建一筆)
    # 邏輯: 如果同 (started_at -> +60s) 內有 created_by=ss_collect 的 run,把那個拿出來合併
    if doc.get("status") == "running":
        # 找 started_at 在自身 之後 5 分鐘內,且有 edges_added 的 record
        from datetime import timedelta
        cutoff = doc["started_at"] + timedelta(minutes=5)
        later = run_col.find_one(
            {
                "started_at": {"$gte": doc["started_at"], "$lte": cutoff},
                "host_count": {"$exists": True},  # seed_collect 寫的才有這欄位
            },
            sort=[("started_at", -1)],
        )
        if later:
            # 把 seed_collect 寫的結果搬上來,更新原本 trigger record
            update = {
                "status": "success",
                "finished_at": later.get("finished_at") or datetime.utcnow(),
                "edges_added": later.get("edges_added", 0),
                "edges_updated": later.get("edges_updated", 0),
                "new_unknowns": later.get("new_unknowns", []),
                "host_count": later.get("host_count", 0),
                "per_host": later.get("per_host", []),
            }
            run_col.update_one({"_id": doc["_id"]}, {"$set": update})
            doc.update(update)

    doc.pop("_id", None)
    return jsonify({"success": True, "data": doc})


@bp.route("/api/dependencies/collect/schedule", methods=["GET"])
@login_required
def collect_schedule_get():
    """讀目前 cron 排程設定"""
    data = dependency_service.get_collect_schedule()
    return jsonify({"success": True, "data": data})


@bp.route("/api/dependencies/collect/schedule", methods=["POST"])
@admin_required
def collect_schedule_set():
    """設定 cron 排程: interval_min (0=disable, 5/10/15/30/60), business_hours_only"""
    body = request.get_json(silent=True) or {}
    try:
        result = dependency_service.set_collect_schedule(
            interval_min=body.get("interval_min", 0),
            business_hours_only=bool(body.get("business_hours_only", True)),
            limit_hosts=body.get("limit_hosts"),
        )
    except ValueError as e:
        return jsonify({"success": False, "error": str(e), "code": 400}), 400
    return jsonify({"success": result["success"], "data": result})


@bp.route("/api/dependencies/collect/runs", methods=["GET"])
@login_required
def collect_runs_list():
    """最近 N 筆 dependency_collect_runs (給 admin tab 顯示歷史)"""
    try:
        limit = max(1, min(int(request.args.get("limit", 20)), 100))
    except (TypeError, ValueError):
        limit = 20
    docs = list(get_collection("dependency_collect_runs").find(
        {}, {"_id": 0, "per_host": 0}
    ).sort("started_at", -1).limit(limit))
    return jsonify({"success": True, "data": docs, "count": len(docs)})


@bp.route("/api/dependencies/upstream", methods=["GET"])
@login_required
def upstream():
    system_id = request.args.get("system_id")
    if not system_id:
        return jsonify({"success": False, "error": "system_id 必填", "code": 400}), 400
    try:
        depth = max(1, min(int(request.args.get("depth", 3)), 6))
    except (TypeError, ValueError):
        depth = 3
    affected = dependency_service.upstream_impact(system_id, max_depth=depth)
    return jsonify({
        "success": True,
        "data": {
            "system_id": system_id,
            "depth": depth,
            "affected_systems": affected,
            "count": len(affected),
        },
    })
