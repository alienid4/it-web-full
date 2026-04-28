from flask import Blueprint, request, jsonify
from decorators import login_required
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.mongo_service import get_all_hosts, get_host, upsert_host, get_hosts_summary

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
    return jsonify({"success": True, "data": h})


@bp.route("/<hostname>/group", methods=["PUT"])
@login_required
def update_host_group(hostname):
    data = request.get_json(force=True)
    group = data.get("group")
    from services.mongo_service import get_collection, get_hosts_col
    get_hosts_col().update_one({"hostname": hostname}, {"$set": {"group": group}})
    return jsonify({"success": True, "message": f"{hostname} 群組已更新為 {group}"})
