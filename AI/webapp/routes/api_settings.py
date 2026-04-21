from flask import Blueprint, request, jsonify
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.mongo_service import get_all_settings, update_setting

bp = Blueprint("api_settings", __name__, url_prefix="/api/settings")


@bp.route("", methods=["GET"])
def list_settings():
    data = get_all_settings()
    return jsonify({"success": True, "data": data})


@bp.route("/<key>", methods=["PUT"])
def edit_setting(key):
    data = request.get_json(force=True)
    value = data.get("value")
    update_setting(key, value)
    return jsonify({"success": True, "message": f"設定 {key} 已更新"})


@bp.route("/version", methods=["GET"])
def get_version():
    import json, os
    vf = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "..", "data", "version.json")
    try:
        with open(vf) as f:
            return jsonify({"success": True, "data": json.load(f)})
    except Exception:
        return jsonify({"success": True, "data": {"version": "unknown"}})
