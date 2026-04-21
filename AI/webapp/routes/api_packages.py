"""軟體套件盤點 API"""
import os
import csv
import io
import json
import subprocess
from datetime import datetime
from flask import Blueprint, request, jsonify, send_file, Response
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from decorators import login_required, admin_required
from services import packages_service

bp = Blueprint("api_packages", __name__, url_prefix="/api/packages")

INSPECTION_HOME = os.environ.get("INSPECTION_HOME", "/opt/inspection")
ANSIBLE_DIR = os.path.join(INSPECTION_HOME, "ansible")
VAULT_PASS = os.path.join(INSPECTION_HOME, ".vault_pass")


@bp.route("", methods=["GET"])
@login_required
def list_hosts():
    """主機清單 + 套件數摘要"""
    data = packages_service.list_hosts_summary()
    return jsonify({"success": True, "data": data, "count": len(data)})


@bp.route("/host/<hostname>", methods=["GET"])
@login_required
def host_detail(hostname):
    """單台完整套件清單 (含 filter)"""
    doc = packages_service.get_host_packages(hostname)
    if not doc:
        return jsonify({"success": False, "error": "主機無盤點資料", "code": 404}), 404
    # optional filter
    q = (request.args.get("q") or "").strip().lower()
    if q and doc.get("packages"):
        doc["packages"] = [p for p in doc["packages"] if q in (p.get("name") or "").lower() or q in (p.get("version") or "").lower()]
        doc["filtered_count"] = len(doc["packages"])
    return jsonify({"success": True, "data": doc})


@bp.route("/search", methods=["GET"])
@login_required
def search():
    """搜套件 → 主機 × 版本分布"""
    q = (request.args.get("q") or "").strip()
    limit = min(int(request.args.get("limit", 100)), 500)
    if not q:
        return jsonify({"success": False, "error": "q required", "code": 400}), 400
    data = packages_service.search_packages(q, limit=limit)
    return jsonify({"success": True, "data": data, "count": len(data), "query": q})


@bp.route("/changes", methods=["GET"])
@login_required
def changes():
    """變更歷史"""
    hostname = request.args.get("host")
    days = int(request.args.get("days", 30))
    limit = min(int(request.args.get("limit", 100)), 500)
    data = packages_service.get_changes(days=days, hostname=hostname, limit=limit)
    return jsonify({"success": True, "data": data, "count": len(data)})


@bp.route("/export/<hostname>", methods=["GET"])
@login_required
def export_host(hostname):
    """下載單台套件清單 (fmt=csv|json)"""
    fmt = (request.args.get("fmt") or "csv").lower()
    doc = packages_service.get_host_packages(hostname)
    if not doc:
        return jsonify({"success": False, "error": "主機無盤點資料", "code": 404}), 404
    packages = doc.get("packages", [])
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    if fmt == "json":
        payload = json.dumps(doc, ensure_ascii=False, indent=2, default=str)
        return Response(
            payload,
            mimetype="application/json",
            headers={"Content-Disposition": f"attachment; filename=packages_{hostname}_{stamp}.json"},
        )

    # csv (default) — add BOM for Excel UTF-8 friendliness
    buf = io.StringIO()
    buf.write("\ufeff")
    writer = csv.writer(buf)
    writer.writerow(["hostname", "os", "kernel", "collected_at", "name", "version", "arch", "install_date"])
    for p in packages:
        writer.writerow([
            doc.get("hostname"),
            doc.get("os"),
            doc.get("kernel"),
            doc.get("collected_at"),
            p.get("name"),
            p.get("version"),
            p.get("arch"),
            p.get("install_date"),
        ])
    return Response(
        buf.getvalue(),
        mimetype="text/csv; charset=utf-8",
        headers={"Content-Disposition": f"attachment; filename=packages_{hostname}_{stamp}.csv"},
    )


@bp.route("/collect", methods=["POST"])
@admin_required
def collect():
    """觸發 Ansible 收集 (非同步 background)"""
    body = request.get_json(silent=True) or {}
    limit = (body.get("limit") or "").strip()  # hostname(s) or empty for all

    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""
    limit_arg = f"--limit {limit}" if limit else ""
    cmd = f"cd {ANSIBLE_DIR} && ansible-playbook -i inventory/hosts.yml {vault_arg} playbooks/collect_packages.yml {limit_arg}"

    # Background run; write log
    logdir = os.path.join(INSPECTION_HOME, "logs")
    os.makedirs(logdir, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    logfile = os.path.join(logdir, f"packages_collect_{stamp}.log")

    # nohup + bg
    full = f"nohup bash -c '{cmd}' > {logfile} 2>&1 &"
    try:
        subprocess.Popen(["bash", "-c", full], close_fds=True)
    except Exception as e:
        return jsonify({"success": False, "error": f"spawn failed: {e}"}), 500

    return jsonify({
        "success": True,
        "message": "收集作業已送出 (背景執行)，完成後呼叫 /import 匯入",
        "log": os.path.basename(logfile),
        "limit": limit or "all",
    })


@bp.route("/import", methods=["POST"])
@admin_required
def do_import():
    """把 data/reports/packages_*.json 匯入 MongoDB + 計算 diff"""
    result = packages_service.import_packages_from_reports()
    return jsonify({"success": True, "data": result})


@bp.route("/collect-and-import", methods=["POST"])
@admin_required
def collect_and_import():
    """一鍵: 同步跑 ansible + 匯入 (適合單台測試，不適合全站 500 台)"""
    body = request.get_json(silent=True) or {}
    limit = (body.get("limit") or "").strip()
    if not limit:
        return jsonify({"success": False, "error": "同步模式必須指定 limit (避免卡太久)"}), 400

    vault_arg = f"--vault-password-file {VAULT_PASS}" if os.path.exists(VAULT_PASS) else ""
    limit_arg = f"--limit {limit}"
    cmd = f"cd {ANSIBLE_DIR} && ansible-playbook -i inventory/hosts.yml {vault_arg} playbooks/collect_packages.yml {limit_arg}"

    try:
        proc = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, timeout=300)
        if proc.returncode != 0:
            return jsonify({
                "success": False,
                "error": "ansible 執行失敗",
                "stderr": proc.stderr[-1500:],
                "stdout_tail": proc.stdout[-1500:],
            }), 500
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "error": "timeout (>300s)"}), 500

    result = packages_service.import_packages_from_reports()
    return jsonify({"success": True, "data": result, "limit": limit})
