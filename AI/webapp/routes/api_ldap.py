from flask import Blueprint, jsonify
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.ldap_service import query_user

bp = Blueprint("api_ldap", __name__, url_prefix="/api/ldap")


@bp.route("/user/<ad_account>", methods=["GET"])
def get_user(ad_account):
    result = query_user(ad_account)
    if not result:
        return jsonify({"success": False, "error": "找不到使用者", "code": 404}), 404
    return jsonify({"success": True, "data": result})
