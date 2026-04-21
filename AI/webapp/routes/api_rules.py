from flask import Blueprint, request, jsonify
from datetime import datetime
import sys, os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from services.mongo_service import get_all_rules, add_rule, update_rule, delete_rule, toggle_rule

bp = Blueprint("api_rules", __name__, url_prefix="/api/rules")


@bp.route("", methods=["GET"])
def list_rules():
    data = get_all_rules()
    return jsonify({"success": True, "data": data, "count": len(data)})


@bp.route("", methods=["POST"])
def create_rule():
    data = request.get_json(force=True)
    now = datetime.now().isoformat()
    doc = {
        "name": data.get("name", ""),
        "type": data.get("type", "keyword"),
        "pattern": data.get("pattern", ""),
        "apply_to": data.get("apply_to", "all"),
        "enabled": data.get("enabled", True),
        "is_known_issue": data.get("is_known_issue", False),
        "known_issue_reason": data.get("known_issue_reason", ""),
        "hit_count": 0,
        "created_at": now,
        "updated_at": now,
    }
    rule_id = add_rule(doc)
    return jsonify({"success": True, "rule_id": rule_id}), 201


@bp.route("/<rule_id>", methods=["PUT"])
def edit_rule(rule_id):
    data = request.get_json(force=True)
    data["updated_at"] = datetime.now().isoformat()
    update_rule(rule_id, data)
    return jsonify({"success": True, "message": "規則已更新"})


@bp.route("/<rule_id>", methods=["DELETE"])
def remove_rule(rule_id):
    delete_rule(rule_id)
    return jsonify({"success": True, "message": "規則已刪除"})


@bp.route("/<rule_id>/toggle", methods=["PUT"])
def toggle(rule_id):
    new_state = toggle_rule(rule_id)
    if new_state is None:
        return jsonify({"success": False, "error": "規則不存在", "code": 404}), 404
    return jsonify({"success": True, "enabled": new_state})
