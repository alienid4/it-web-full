"""認證裝飾器"""
from functools import wraps
from flask import session, redirect, url_for, jsonify, request


def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            if request.path.startswith("/api/"):
                return jsonify({"success": False, "error": "未登入", "code": 401}), 401
            return redirect("/login?next=" + request.path)
        return f(*args, **kwargs)
    return decorated


def admin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if "user_id" not in session:
            if request.path.startswith("/api/"):
                return jsonify({"success": False, "error": "未登入", "code": 401}), 401
            return redirect("/login")
        if session.get("role") not in ("admin", "superadmin"):
            if request.path.startswith("/api/"):
                return jsonify({"success": False, "error": "權限不足", "code": 403}), 403
            return redirect("/")
        return f(*args, **kwargs)
    return decorated
