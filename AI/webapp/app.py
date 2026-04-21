#!/usr/bin/env python3
"""金融業 IT 每日自動巡檢系統 - Flask 主程式"""
from flask import Flask, render_template, redirect, session, request
from datetime import datetime
from config import FLASK_HOST, FLASK_PORT, FLASK_DEBUG, SECRET_KEY

app = Flask(__name__,
            template_folder="templates",
            static_folder="static")
app.secret_key = SECRET_KEY
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

# 確保預設 admin 帳號存在
from services.auth_service import ensure_default_admin
with app.app_context():
    ensure_default_admin()


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


@app.route("/superadmin")
def superadmin_page():
    if session.get("role") != "superadmin":
        return redirect("/login")
    return render_template("superadmin.html")


if __name__ == "__main__":
    app.run(host=FLASK_HOST, port=FLASK_PORT, debug=FLASK_DEBUG)
