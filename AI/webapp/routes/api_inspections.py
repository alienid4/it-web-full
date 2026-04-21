from flask import Blueprint, request, jsonify
from decorators import login_required
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.mongo_service import (
    get_summary_report,
    get_latest_inspections, get_host_latest_inspection,
    get_host_history, get_abnormal_inspections, get_trend
)

bp = Blueprint("api_inspections", __name__, url_prefix="/api/inspections")


@bp.route("/latest", methods=["GET"])
@login_required
def latest():
    data = get_latest_inspections()
    return jsonify({"success": True, "data": data, "count": len(data)})


@bp.route("/<hostname>/latest", methods=["GET"])
@login_required
def host_latest(hostname):
    doc = get_host_latest_inspection(hostname)
    if not doc:
        return jsonify({"success": False, "error": "無巡檢資料", "code": 404}), 404
    return jsonify({"success": True, "data": doc})


@bp.route("/<hostname>/history", methods=["GET"])
@login_required
def host_history(hostname):
    days = request.args.get("days", 7, type=int)
    data = get_host_history(hostname, days)
    return jsonify({"success": True, "data": data, "count": len(data)})


@bp.route("/abnormal", methods=["GET"])
@login_required
def abnormal():
    data = get_abnormal_inspections()
    return jsonify({"success": True, "data": data, "count": len(data)})


@bp.route("/trend", methods=["GET"])
def trend():
    days = request.args.get("days", 7, type=int)
    data = get_trend(days)
    return jsonify({"success": True, "data": data})


@bp.route("/summary", methods=["GET"])
def summary():
    data = get_summary_report()
    return jsonify({"success": True, "data": data})
