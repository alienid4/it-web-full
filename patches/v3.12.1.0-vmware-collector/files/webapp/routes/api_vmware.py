#!/usr/bin/env python3
# v3.12.1.0: 改從 vmware_service 讀 (MongoDB 有就 MongoDB, 沒就 fallback inline mock)

from flask import Blueprint, render_template, jsonify, session

bp = Blueprint("vmware", __name__)


@bp.route("/vmware")
def vmware_overview_page():
    """主管開門版總覽頁"""
    from services.vmware_service import get_overview_data
    data = get_overview_data()
    return render_template("vmware.html", vm=data)


@bp.route("/api/vmware/overview")
def api_overview():
    """JSON API"""
    if not session.get("username"):
        return jsonify({"success": False, "error": "unauthorized"}), 401
    from services.vmware_service import get_overview_data
    return jsonify({"success": True, "data": get_overview_data()})
