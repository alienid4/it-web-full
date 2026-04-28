#!/usr/bin/env python3
"""金融業 IT 每日自動巡檢系統 - Flask 主程式"""
from flask import Flask, render_template, redirect, session, request
import os
from datetime import datetime
from config import FLASK_HOST, FLASK_PORT, FLASK_DEBUG, SECRET_KEY

app = Flask(__name__,
            template_folder="templates",
            static_folder="static")
app.secret_key = SECRET_KEY

# ===== 2026-04-20: 全站強制登入 =====
_PUBLIC_PATHS = {"/login", "/api/admin/login", "/api/settings/version", "/favicon.ico"}

@app.before_request
def _enforce_login_before_request():
    from flask import request, session, redirect, jsonify
    p = request.path or "/"
    # 白名單: 靜態資源, 明確公開路徑
    if p.startswith("/static/"):
        return None
    if p in _PUBLIC_PATHS:
        return None
    if session.get("user_id"):
        return None
    # 未登入: API 回 401, 頁面導到 /login
    if p.startswith("/api/"):
        return jsonify({"success": False, "error": "未登入", "code": 401}), 401
    return redirect("/login?next=" + p)
# ===================================

app.config["SESSION_COOKIE_HTTPONLY"] = True
app.config["SESSION_COOKIE_SAMESITE"] = "Lax"
app.config["PERMANENT_SESSION_LIFETIME"] = 28800  # 8 hours

# 追蹤在線使用者 — 每次 API 請求時更新 last_seen
@app.before_request
def track_active_user():
    username = session.get("username")
    if username and request.path.startswith("/api/"):
        try:
            from services.mongo_service import get_db
            db = get_db()
            db.users.update_one(
                {"username": username},
                {"$set": {
                    "last_seen": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
                    "last_ip": request.remote_addr,
                }}
            )
        except Exception:
            pass  # 追蹤失敗不影響正常功能

# M-01: 安全 HTTP Headers + M-02: 隱藏 Server
@app.after_request
def add_security_headers(response):
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    response.headers["Permissions-Policy"] = "geolocation=(), microphone=(), camera=()"
    response.headers["X-XSS-Protection"] = "1; mode=block"
    # HTML 頁面禁止 cache (JS/CSS/HTML 變更能立刻見效)
    if response.mimetype == "text/html":
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        response.headers["Pragma"] = "no-cache"
    response.headers["Content-Security-Policy"] = "default-src 'self' 'unsafe-inline' 'unsafe-eval' https://fonts.googleapis.com https://fonts.gstatic.com https://cdn.jsdelivr.net"
    del response.headers["Server"]; response.headers["Server"] = ""
    return response

# 註冊 Blueprints
from routes.api_hosts import bp as hosts_bp
from routes.api_inspections import bp as inspections_bp
from routes.api_rules import bp as rules_bp
from routes.api_settings import bp as settings_bp
from routes.api_ldap import bp as ldap_bp
from routes.api_admin import bp as admin_bp
from routes.api_audit import bp as audit_bp
from routes.api_twgcb import bp as twgcb_bp
from routes.api_harden import bp as harden_bp
from routes.api_superadmin import bp as superadmin_bp
from routes.api_security_audit import bp as security_audit_bp
from routes.api_linux_init import bp as linux_init_bp
from routes.api_packages import bp as packages_bp
from routes.api_nmon import bp as nmon_bp
from routes.api_cio import bp as cio_bp
from routes.api_deep_check import bp as deep_check_bp
from routes.api_vmware import bp as vmware_bp
from routes.api_dependencies import bp as dependencies_bp

app.register_blueprint(hosts_bp)
app.register_blueprint(inspections_bp)
app.register_blueprint(rules_bp)
app.register_blueprint(settings_bp)
app.register_blueprint(ldap_bp)
app.register_blueprint(audit_bp)
app.register_blueprint(admin_bp)
app.register_blueprint(twgcb_bp)
app.register_blueprint(harden_bp)
app.register_blueprint(superadmin_bp)
app.register_blueprint(security_audit_bp)
app.register_blueprint(linux_init_bp)
app.register_blueprint(packages_bp)
app.register_blueprint(nmon_bp)
app.register_blueprint(cio_bp)
app.register_blueprint(deep_check_bp)
app.register_blueprint(vmware_bp)
app.register_blueprint(dependencies_bp)

# 確保預設 admin 帳號存在
# v3.9.3.0: static asset cache busting (自動帶 ?v=版本)
import json as _json
def _load_app_version():
    try:
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "version.json"), encoding="utf-8") as _f:
            return _json.load(_f).get("version", "dev")
    except Exception:
        return "dev"
_APP_VER = _load_app_version()

@app.context_processor
def _inject_app_version():
    return {"APP_VER": _APP_VER}


# ===== 2026-04-20: Feature Flag System =====
# 每個 feature key 對應到哪些 URL 要擋 (前綴 match)
_FEATURE_PATH_MAP = [
    ("audit",          ["/audit", "/api/audit"]),
    ("packages",       ["/packages", "/api/packages"]),
    ("perf",           ["/perf", "/api/nmon"]),
    ("twgcb",          ["/twgcb", "/api/twgcb", "/api/harden"]),
    ("summary",        ["/summary"]),
    ("security_audit", ["/api/security-audit", "/api/security_audit"]),
    ("vmware",         ["/vmware", "/api/vmware"]),
    ("dependencies",   ["/dependencies", "/api/dependencies"]),
]


def _feature_for_path(path):
    for key, prefixes in _FEATURE_PATH_MAP:
        for p in prefixes:
            if path == p or path.startswith(p + "/") or path.startswith(p + "?"):
                return key
    return None


@app.before_request
def _check_feature_flag():
    from flask import request, jsonify, redirect
    p = request.path or "/"
    if p.startswith("/static/") or p == "/feature-disabled":
        return None
    key = _feature_for_path(p)
    if not key:
        return None
    from services import feature_flags
    flags = feature_flags.all_flags()
    if flags.get(key, True):
        return None
    # 模組已關
    if p.startswith("/api/"):
        return jsonify({"success": False, "error": "模組未開通", "module": key, "code": 402}), 402
    return redirect("/feature-disabled?m=" + key)


@app.context_processor
def _inject_features():
    # 把 feature flags 注入所有 template (讓 nav / admin 用 {% if FEATURES.xxx %})
    try:
        from services import feature_flags
        return {"FEATURES": feature_flags.all_flags()}
    except Exception:
        return {"FEATURES": {}}


@app.route("/feature-disabled")
def feature_disabled_page():
    from flask import request
    key = request.args.get("m", "")
    try:
        from services import feature_flags
        flags = {f["key"]: f for f in feature_flags.list_flags()}
    except Exception:
        flags = {}
    info = flags.get(key, {})
    return render_template("feature_disabled.html", module=key,
                           module_name=info.get("name", key),
                           description=info.get("description", ""))
# ===== Feature Flag end =====

from services.auth_service import ensure_default_admin
from services import dependency_service as _dep_svc
with app.app_context():
    ensure_default_admin()
    try:
        _dep_svc.ensure_indexes()
    except Exception as _e:
        print(f"[WARN] dependency_service.ensure_indexes 失敗: {_e}")


# 在線使用者 API
from flask import jsonify as _jsonify
from services.mongo_service import get_db as _get_db

@app.route("/api/admin/online-users", methods=["GET"])
def online_users():
    if not session.get("username"):
        return _jsonify({"success": False}), 401
    db = _get_db()
    users = list(db.users.find(
        {"last_seen": {"$exists": True}},
        {"_id": 0, "username": 1, "display_name": 1, "role": 1, "last_seen": 1, "last_ip": 1}
    ))
    # 計算在線狀態（30 分鐘內有活動 = online）
    now = datetime.now()
    result = []
    for u in users:
        try:
            seen = datetime.strptime(u["last_seen"], "%Y-%m-%d %H:%M:%S")
            diff_min = (now - seen).total_seconds() / 60
            status = "online" if diff_min <= 30 else "offline"
        except Exception:
            diff_min = 999
            status = "offline"
        result.append({
            "username": u.get("username"),
            "display_name": u.get("display_name", u.get("username")),
            "role": u.get("role", ""),
            "last_seen": u.get("last_seen", ""),
            "last_ip": u.get("last_ip", ""),
            "status": status,
            "minutes_ago": round(diff_min),
        })
    result.sort(key=lambda x: x["last_seen"], reverse=True)
    online_count = sum(1 for u in result if u["status"] == "online")
    return _jsonify({"success": True, "online_count": online_count, "total": len(result), "data": result})


@app.route("/")
def index():
    return render_template("dashboard.html")


@app.route("/report")
def report_page():
    return render_template("report.html")


@app.route("/report/<hostname>")
def host_report_page(hostname):
    return render_template("host_detail.html", hostname=hostname)


@app.route("/history")
def history_page():
    return render_template("history.html")


@app.route("/hosts")
def hosts_page():
    return render_template("hosts.html")


@app.route("/rules")
def rules_page():
    return render_template("filter_rules.html")


@app.route("/audit")
def audit_page():
    return render_template("audit.html")


@app.route("/packages")
def packages_page():
    return render_template("packages.html")


@app.route("/perf")
def perf_page():
    return render_template("perf.html")


@app.route("/executive")
def executive_page():
    return render_template("executive.html")




@app.route("/twgcb")
def twgcb_page():
    return render_template("twgcb.html")


@app.route("/twgcb/<hostname>")
def twgcb_detail_page(hostname):
    return render_template("twgcb_detail.html", hostname=hostname)


@app.route("/twgcb/harden/<hostname>")
def twgcb_harden_page(hostname):
    return render_template("twgcb_harden.html", hostname=hostname)


@app.route("/twgcb-report")
def twgcb_report_page():
    return render_template("twgcb_report.html")


@app.route("/twgcb-settings")
def twgcb_settings_page():
    return render_template("twgcb_settings.html")


@app.route("/summary")
def summary_page():
    return render_template("summary.html")


@app.route("/reset-password")
def reset_password_page():
    return render_template("reset_password.html")


@app.route("/login")
def login_page():
    return render_template("login.html")


@app.route("/admin")
def admin_page():
    # oper（未登入）可瀏覽但操作受限，前端 JS 會控制
    return render_template("admin.html")


@app.route("/admin/host-edit/new")
def admin_host_edit_new():
    return render_template("host_edit.html", hostname="", is_new=True)

@app.route("/admin/host-edit/<hostname>")
def admin_host_edit(hostname):
    return render_template("host_edit.html", hostname=hostname, is_new=False)


@app.route("/superadmin")
def superadmin_page():
    if session.get("role") != "superadmin":
        return redirect("/login")
    return render_template("superadmin.html")


if __name__ == "__main__":
    app.run(host=FLASK_HOST, port=FLASK_PORT, debug=FLASK_DEBUG, threaded=True)
