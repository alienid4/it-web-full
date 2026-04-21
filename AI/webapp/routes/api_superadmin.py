"""超級管理員 API - GitHub 推送 + 系統級操作 + 開發者文件"""
from flask import Blueprint, jsonify, request, session, send_file
from functools import wraps
import subprocess
import os
import json
from services.auth_service import log_action
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


COMMIT_NOTES_FILE = os.path.join(INSPECTION_HOME, "data", "commit_notes.json")


def _load_notes():
    if os.path.exists(COMMIT_NOTES_FILE):
        with open(COMMIT_NOTES_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def _save_notes(notes):
    os.makedirs(os.path.dirname(COMMIT_NOTES_FILE), exist_ok=True)
    with open(COMMIT_NOTES_FILE, "w", encoding="utf-8") as f:
        json.dump(notes, f, ensure_ascii=False, indent=2)


@bp.route("/git/notes", methods=["GET"])
@superadmin_required
def get_commit_notes():
    """取得所有 commit 備註"""
    return jsonify({"success": True, "data": _load_notes()})


@bp.route("/git/notes/<commit_hash>", methods=["PUT"])
@superadmin_required
def set_commit_note(commit_hash):
    """設定單筆 commit 備註或訊息覆寫"""
    data = request.json if request.is_json else {}
    notes = _load_notes()
    entry = notes.get(commit_hash, {})
    if isinstance(entry, str):
        entry = {"note": entry}
    if "note" in data:
        entry["note"] = data["note"].strip()
    if "msg" in data:
        entry["msg"] = data["msg"].strip()
    # 清除空值
    entry = {k: v for k, v in entry.items() if v}
    if entry:
        notes[commit_hash] = entry
    else:
        notes.pop(commit_hash, None)
    _save_notes(notes)
    return jsonify({"success": True})


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


# ========== Developer Docs ==========
DOCS_MAP = {
    "handoff": {"name": "專案接手文件", "path": "data/PROJECT_HANDOFF.md", "desc": "完整功能總覽、目錄結構、MongoDB collections、版本歷程"},
    "spec": {"name": "規格變更紀錄", "path": "data/SPEC_CHANGELOG_20260410.md", "desc": "19 項變更需求"},
    "devlog": {"name": "開發者日記", "path": "data/DEVLOG.md", "desc": "開發歷程、技術決策紀錄"},
    "worklog": {"name": "工作日誌", "path": "data/worklog.log", "desc": "AI 逐項工作紀錄"},
    "version": {"name": "版本號", "path": "data/version.json", "desc": "changelog 歷程"},
    "skill": {"name": "Inspection Skill", "path": "data/SKILL.md", "desc": "AI 開發接手流程與規範"},
    "memory": {"name": "專案記憶", "path": "data/project_memory.md", "desc": "規格變更摘要"},
    "itagent_manual": {"name": "服務管理手冊", "path": "data/ITAGENT_MANUAL.md", "desc": "ITAgent systemd 服務架構、日常操作、搬家步驟、故障排除"},
    "itagent_script": {"name": "管理腳本", "path": "itagent.sh", "desc": "互動式選單 + CLI 模式（start/stop/restart/status/log）"},
}


@bp.route("/docs/list", methods=["GET"])
@superadmin_required
def docs_list():
    """列出所有開發者文件"""
    result = []
    for doc_id, info in DOCS_MAP.items():
        fpath = os.path.join(INSPECTION_HOME, info["path"])
        exists = os.path.exists(fpath)
        size = os.path.getsize(fpath) if exists else 0
        mtime = datetime.fromtimestamp(os.path.getmtime(fpath)).strftime("%Y-%m-%d %H:%M") if exists else ""
        result.append({
            "id": doc_id,
            "name": info["name"],
            "desc": info["desc"],
            "filename": os.path.basename(info["path"]),
            "size": size,
            "size_kb": round(size / 1024, 1),
            "mtime": mtime,
            "exists": exists,
        })
    return jsonify({"success": True, "data": result})


@bp.route("/docs/view/<doc_id>", methods=["GET"])
@superadmin_required
def docs_view(doc_id):
    """檢視文件內容"""
    if doc_id not in DOCS_MAP:
        return jsonify({"success": False, "error": "文件不存在"}), 404
    fpath = os.path.join(INSPECTION_HOME, DOCS_MAP[doc_id]["path"])
    if not os.path.exists(fpath):
        return jsonify({"success": False, "error": "檔案不存在"}), 404
    with open(fpath, "r", encoding="utf-8") as f:
        content = f.read()
    return jsonify({"success": True, "data": {"content": content, "name": DOCS_MAP[doc_id]["name"]}})


@bp.route("/docs/download/<doc_id>", methods=["GET"])
@superadmin_required
def docs_download(doc_id):
    """下載文件"""
    if doc_id not in DOCS_MAP:
        return jsonify({"success": False, "error": "文件不存在"}), 404
    fpath = os.path.join(INSPECTION_HOME, DOCS_MAP[doc_id]["path"])
    if not os.path.exists(fpath):
        return jsonify({"success": False, "error": "檔案不存在"}), 404
    return send_file(fpath, as_attachment=True, download_name=os.path.basename(fpath))


# ===== 系統打包下載 API =====

@bp.route("/download-package", methods=["POST"])
@superadmin_required
def download_package():
    """打包系統為 tar.gz 並提供下載連結"""
    import time
    ts = time.strftime("%Y%m%d_%H%M%S")
    filename = "inspection_deploy_v%s_%s.tar.gz" % (
        json.load(open(os.path.join(INSPECTION_HOME, "data/version.json"))).get("version", "unknown"),
        ts
    )
    filepath = os.path.join("/tmp", filename)
    try:
        # 完整打包（排除 .git 和 MongoDB 資料卷）
        subprocess.run(
            ["tar", "czf", filepath,
             "--exclude=.git",
             "--exclude=container/mongodb_data",
             "-C", "/opt", "inspection/"],
            check=True, timeout=120
        )
        size_mb = os.path.getsize(filepath) / 1024 / 1024
        log_action(session.get("username", "unknown"), "download_package",
            "打包部署包: %s (%.1f MB)" % (filename, size_mb), request.remote_addr)
        return jsonify({"success": True, "filename": filename, "size_mb": round(size_mb, 1),
                        "download_url": "/api/superadmin/download-package/" + filename})
    except Exception as e:
        return jsonify({"success": False, "error": str(e)}), 500


@bp.route("/download-package/<filename>", methods=["GET"])
@superadmin_required
def download_package_file(filename):
    """下載打包檔案"""
    filepath = os.path.join("/tmp", filename)
    if not os.path.exists(filepath):
        return jsonify({"success": False, "error": "檔案不存在"}), 404
    return send_file(filepath, as_attachment=True, download_name=filename)



# ========== File Upload / Download ==========
UPLOAD_DIR = os.path.join(INSPECTION_HOME, "data", "uploads")
NOTES_DIR = os.path.join(INSPECTION_HOME, "data", "notes")
ALLOWED_EXTENSIONS = {".txt", ".md", ".json", ".csv", ".yml", ".yaml", ".py", ".sh", ".conf", ".log", ".xlsx", ".pdf", ".tar.gz", ".zip"}


@bp.route("/file/list", methods=["GET"])
@superadmin_required
def file_list():
    """列出上傳的檔案"""
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    files = []
    for f in os.listdir(UPLOAD_DIR):
        fpath = os.path.join(UPLOAD_DIR, f)
        if os.path.isfile(fpath):
            files.append({
                "name": f,
                "size_kb": round(os.path.getsize(fpath) / 1024, 1),
                "mtime": datetime.fromtimestamp(os.path.getmtime(fpath)).strftime("%Y-%m-%d %H:%M"),
            })
    files.sort(key=lambda x: x["mtime"], reverse=True)
    return jsonify({"success": True, "data": files})


@bp.route("/file/upload", methods=["POST"])
@superadmin_required
def file_upload():
    """上傳檔案"""
    os.makedirs(UPLOAD_DIR, exist_ok=True)
    if "file" not in request.files:
        return jsonify({"success": False, "error": "沒有檔案"}), 400
    f = request.files["file"]
    if not f.filename:
        return jsonify({"success": False, "error": "檔案名稱為空"}), 400
    # 安全檔名
    from werkzeug.utils import secure_filename
    filename = secure_filename(f.filename)
    if not filename:
        filename = "upload_" + datetime.now().strftime("%Y%m%d_%H%M%S")
    f.save(os.path.join(UPLOAD_DIR, filename))
    return jsonify({"success": True, "message": "上傳成功: " + filename, "filename": filename})


@bp.route("/file/download/<filename>", methods=["GET"])
@superadmin_required
def file_download(filename):
    """下載檔案"""
    from werkzeug.utils import secure_filename
    safe = secure_filename(filename)
    fpath = os.path.join(UPLOAD_DIR, safe)
    if not os.path.exists(fpath):
        return jsonify({"success": False, "error": "檔案不存在"}), 404
    return send_file(fpath, as_attachment=True, download_name=safe)


@bp.route("/file/delete/<filename>", methods=["DELETE"])
@superadmin_required
def file_delete(filename):
    """刪除檔案"""
    from werkzeug.utils import secure_filename
    safe = secure_filename(filename)
    fpath = os.path.join(UPLOAD_DIR, safe)
    if os.path.exists(fpath):
        os.remove(fpath)
    return jsonify({"success": True, "message": "已刪除: " + safe})


# ========== Notes (備忘錄) ==========
@bp.route("/notes/list", methods=["GET"])
@superadmin_required
def notes_list():
    """列出所有備忘錄"""
    os.makedirs(NOTES_DIR, exist_ok=True)
    notes = []
    for f in sorted(os.listdir(NOTES_DIR), reverse=True):
        if f.endswith(".txt"):
            fpath = os.path.join(NOTES_DIR, f)
            with open(fpath, "r", encoding="utf-8") as fh:
                preview = fh.read(200)
            notes.append({
                "id": f.replace(".txt", ""),
                "filename": f,
                "preview": preview,
                "mtime": datetime.fromtimestamp(os.path.getmtime(fpath)).strftime("%Y-%m-%d %H:%M"),
            })
    return jsonify({"success": True, "data": notes})


@bp.route("/notes/save", methods=["POST"])
@superadmin_required
def notes_save():
    """儲存備忘錄"""
    os.makedirs(NOTES_DIR, exist_ok=True)
    data = request.get_json(force=True)
    title = data.get("title", "").strip() or datetime.now().strftime("note_%Y%m%d_%H%M%S")
    content = data.get("content", "")
    # 安全檔名
    safe_title = "".join(c for c in title if c.isalnum() or c in "-_ ").strip()[:50]
    if not safe_title:
        safe_title = datetime.now().strftime("note_%Y%m%d_%H%M%S")
    filename = safe_title + ".txt"
    with open(os.path.join(NOTES_DIR, filename), "w", encoding="utf-8") as f:
        f.write(content)
    return jsonify({"success": True, "message": "已儲存: " + filename, "filename": filename})


@bp.route("/notes/view/<note_id>", methods=["GET"])
@superadmin_required
def notes_view(note_id):
    """檢視備忘錄"""
    fpath = os.path.join(NOTES_DIR, note_id + ".txt")
    if not os.path.exists(fpath):
        return jsonify({"success": False, "error": "不存在"}), 404
    with open(fpath, "r", encoding="utf-8") as f:
        content = f.read()
    return jsonify({"success": True, "data": {"content": content, "id": note_id}})


@bp.route("/notes/delete/<note_id>", methods=["DELETE"])
@superadmin_required
def notes_delete(note_id):
    """刪除備忘錄"""
    fpath = os.path.join(NOTES_DIR, note_id + ".txt")
    if os.path.exists(fpath):
        os.remove(fpath)
    return jsonify({"success": True})
