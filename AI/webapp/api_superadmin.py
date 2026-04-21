"""超級管理員 API - GitHub 推送 + 系統級操作"""
from flask import Blueprint, jsonify, request, session
from functools import wraps
import subprocess
import os
from datetime import datetime

bp = Blueprint("api_superadmin", __name__, url_prefix="/api/superadmin")

INSPECTION_HOME = "/opt/inspection"


def superadmin_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if not session.get("username"):
            return jsonify({"success": False, "error": "未登入"}), 401
        if session.get("role") != "superadmin":
            return jsonify({"success": False, "error": "需要超級管理員權限"}), 403
        return f(*args, **kwargs)
    return decorated


@bp.route("/check-auth", methods=["GET"])
def check_auth():
    """檢查是否為超級管理員"""
    if not session.get("username"):
        return jsonify({"success": False, "error": "未登入"}), 401
    return jsonify({
        "success": True,
        "username": session.get("username"),
        "role": session.get("role"),
        "is_superadmin": session.get("role") == "superadmin"
    })


@bp.route("/git/status", methods=["GET"])
@superadmin_required
def git_status():
    """取得 Git 狀態"""
    try:
        # status
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=INSPECTION_HOME, capture_output=True, text=True, timeout=10
        )
        # log
        log = subprocess.run(
            ["git", "log", "--format=%h|%ci|%s", "-10"],
            cwd=INSPECTION_HOME, capture_output=True, text=True, timeout=10
        )
        # remote
        remote = subprocess.run(
            ["git", "remote", "-v"],
            cwd=INSPECTION_HOME, capture_output=True, text=True, timeout=10
        )
        # branch
        branch = subprocess.run(
            ["git", "branch", "--show-current"],
            cwd=INSPECTION_HOME, capture_output=True, text=True, timeout=10
        )

        changed_files = [l for l in status.stdout.strip().split("\n") if l.strip()]

        return jsonify({
            "success": True,
            "data": {
                "branch": branch.stdout.strip(),
                "remote": remote.stdout.strip(),
                "changed_files": changed_files,
                "changed_count": len(changed_files),
                "recent_commits": log.stdout.strip().split("\n") if log.stdout.strip() else []
            }
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@bp.route("/git/push", methods=["POST"])
@superadmin_required
def git_push():
    """Commit + Push 到 GitHub"""
    message = ""
    if request.is_json:
        message = request.json.get("message", "").strip()

    if not message:
        # 自動產生 commit message
        with open(os.path.join(INSPECTION_HOME, "data", "version.json")) as f:
            import json
            ver = json.load(f)
        message = "v" + ver.get("version", "?") + " - " + datetime.now().strftime("%Y-%m-%d %H:%M")

    try:
        # git add
        add_result = subprocess.run(
            ["git", "add", "-A"],
            cwd=INSPECTION_HOME, capture_output=True, text=True, timeout=10
        )

        # 檢查是否有變更
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=INSPECTION_HOME, capture_output=True, text=True, timeout=10
        )
        if not status.stdout.strip():
            return jsonify({"success": True, "message": "沒有變更需要推送", "pushed": False})

        # git commit
        commit_result = subprocess.run(
            ["git", "commit", "-m", message],
            cwd=INSPECTION_HOME, capture_output=True, text=True, timeout=10
        )
        if commit_result.returncode != 0:
            return jsonify({"success": False, "error": "Commit 失敗: " + commit_result.stderr}), 500

        # git push
        push_result = subprocess.run(
            ["git", "push", "origin", "main"],
            cwd=INSPECTION_HOME, capture_output=True, text=True, timeout=30
        )
        if push_result.returncode != 0:
            return jsonify({"success": False, "error": "Push 失敗: " + push_result.stderr}), 500

        return jsonify({
            "success": True,
            "message": "已推送到 GitHub",
            "pushed": True,
            "commit_message": message,
            "output": commit_result.stdout[:500]
        })
    except subprocess.TimeoutExpired:
        return jsonify({"success": False, "error": "操作超時"}), 504
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@bp.route("/git/diff", methods=["GET"])
@superadmin_required
def git_diff():
    """查看未提交的變更內容"""
    try:
        diff = subprocess.run(
            ["git", "diff", "--stat"],
            cwd=INSPECTION_HOME, capture_output=True, text=True, timeout=10
        )
        diff_cached = subprocess.run(
            ["git", "diff", "--cached", "--stat"],
            cwd=INSPECTION_HOME, capture_output=True, text=True, timeout=10
        )
        return jsonify({
            "success": True,
            "data": {
                "unstaged": diff.stdout,
                "staged": diff_cached.stdout
            }
        })
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500
