from flask import Blueprint, request, jsonify
from decorators import login_required
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.mongo_service import get_all_hosts, get_host, upsert_host, get_hosts_summary
from services.actuals_service import annotate_hosts, annotate_host, adopt_actual

bp = Blueprint("api_hosts", __name__, url_prefix="/api/hosts")


@bp.route("", methods=["GET"])
@login_required
def list_hosts():
    page = request.args.get("page", 1, type=int)
    per_page = request.args.get("per_page", 50, type=int)
    os_group = request.args.get("os_group")
    status = request.args.get("status")
    q = {}
    if os_group:
        q["os_group"] = os_group
    if status:
        q["status"] = status
    result = get_all_hosts(q, page, per_page)
    # v3.17.9.0+: 對照 inspections 偵測值, 加 _actuals/_mismatches
    if isinstance(result.get("data"), list):
        annotate_hosts(result["data"])
    return jsonify({"success": True, **result})


@bp.route("/summary", methods=["GET"])
@login_required
def hosts_summary():
    return jsonify({"success": True, "data": get_hosts_summary()})


@bp.route("/<hostname>", methods=["GET"])
@login_required
def host_detail(hostname):
    h = get_host(hostname)
    if not h:
        return jsonify({"success": False, "error": "主機不存在", "code": 404}), 404
    # v3.17.9.0+
    annotate_host(h)
    return jsonify({"success": True, "data": h})


@bp.route("/<hostname>/group", methods=["PUT"])
@login_required
def update_host_group(hostname):
    data = request.get_json(force=True)
    group = data.get("group")
    from services.mongo_service import get_collection
    get_collection("hosts").update_one({"hostname": hostname}, {"$set": {"group": group}})
    return jsonify({"success": True, "message": f"{hostname} 群組已更新為 {group}"})


@bp.route("/<hostname>/adopt-actual", methods=["POST"])
@login_required
def host_adopt_actual(hostname):
    """v3.17.9.0+: 把實際偵測值採用到 hosts (POST body: {"field": "os"})"""
    from decorators import admin_required
    data = request.get_json(force=True) or {}
    field = data.get("field", "")
    ok, msg = adopt_actual(hostname, field)
    return (jsonify({"success": True, "message": msg}) if ok else
            (jsonify({"success": False, "error": msg}), 400))
