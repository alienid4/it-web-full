#!/usr/bin/env python3
# v3.12.0.0 W1: VMware 管理 blueprint (頁 + API)
# 目前使用 vmware_mock 假資料；W1 後續會改接 MongoDB snapshot

from flask import Blueprint, render_template, jsonify, session

bp = Blueprint("vmware", __name__)


@bp.route("/vmware")
def vmware_overview_page():
    """主管開門版總覽頁"""
    from services.vmware_mock import get_overview_data
    data = get_overview_data()
    return render_template("vmware.html", vm=data)


@bp.route("/api/vmware/overview")
def api_overview():
    """JSON API，給 AJAX 未來重抓或前端更新用"""
    if not session.get("username"):
        return jsonify({"success": False, "error": "unauthorized"}), 401
    from services.vmware_mock import get_overview_data
    return jsonify({"success": True, "data": get_overview_data()})
