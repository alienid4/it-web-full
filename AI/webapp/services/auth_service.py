"""認證服務"""
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime, timedelta
from services.mongo_service import get_collection
import secrets

# H-05: 登入失敗鎖定設定
LOGIN_MAX_ATTEMPTS = 5
LOGIN_LOCKOUT_MINUTES = 15

# 密碼重設 token 有效時間
RESET_TOKEN_EXPIRE_MINUTES = 30


def get_user(username):
    return get_collection("users").find_one({"username": username}, {"_id": 0})


def check_login_lockout(username):
    """檢查帳號是否被鎖定"""
    col = get_collection("login_attempts")
    record = col.find_one({"username": username})
    if not record:
        return False
    if record.get("locked_until"):
        locked_until = datetime.fromisoformat(record["locked_until"])
        if datetime.now() < locked_until:
            return True
        else:
            # 鎖定時間過了，重置
            col.delete_one({"username": username})
            return False
    return False


def record_login_failure(username):
    """記錄登入失敗"""
    col = get_collection("login_attempts")
    record = col.find_one({"username": username})
    if record:
        attempts = record.get("attempts", 0) + 1
        update = {"$set": {"attempts": attempts, "last_attempt": datetime.now().isoformat()}}
        if attempts >= LOGIN_MAX_ATTEMPTS:
            locked_until = (datetime.now() + timedelta(minutes=LOGIN_LOCKOUT_MINUTES)).isoformat()
            update["$set"]["locked_until"] = locked_until
        col.update_one({"username": username}, update)
    else:
        col.insert_one({"username": username, "attempts": 1, "last_attempt": datetime.now().isoformat()})


def reset_login_attempts(username):
    """登入成功後重置"""
    get_collection("login_attempts").delete_one({"username": username})


def create_user(username, password, role="viewer", display_name="", email=""):
    col = get_collection("users")
    if col.find_one({"username": username}):
        return None
    doc = {
        "username": username,
        "password_hash": generate_password_hash(password),
        "role": role,
        "display_name": display_name or username,
        "email": email,
        "must_change_password": True,
        "created_at": datetime.now().isoformat(),
        "last_login": None,
    }
    col.insert_one(doc)
    return username


def verify_login(username, password):
    # C-03: NoSQL Injection 防護 — 強制輸入為 string
    if not isinstance(username, str) or not isinstance(password, str):
        return None
    if len(username) > 100 or len(password) > 200:
        return None
    # H-05: 檢查鎖定
    if check_login_lockout(username):
        return "LOCKED"
    user = get_user(username)
    if not user:
        record_login_failure(username)
        return None
    if not check_password_hash(user["password_hash"], password):
        record_login_failure(username)
        return None
    # 登入成功，重置計數
    reset_login_attempts(username)
    get_collection("users").update_one(
        {"username": username},
        {"$set": {"last_login": datetime.now().isoformat()}}
    )
    return user


def change_password(username, new_password):
    get_collection("users").update_one(
        {"username": username},
        {"$set": {
            "password_hash": generate_password_hash(new_password),
            "must_change_password": False,
        }}
    )


def generate_reset_token(username):
    """產生密碼重設 token，存入 DB，回傳 token"""
    user = get_user(username)
    if not user or not user.get("email"):
        return None, None
    token = secrets.token_urlsafe(32)
    expires = (datetime.now() + timedelta(minutes=RESET_TOKEN_EXPIRE_MINUTES)).isoformat()
    col = get_collection("password_resets")
    col.delete_many({"username": username})  # 清除舊的
    col.insert_one({
        "username": username,
        "token": token,
        "expires": expires,
        "created_at": datetime.now().isoformat(),
    })
    return token, user["email"]


def verify_reset_token(token):
    """驗證 token，回傳 username 或 None"""
    col = get_collection("password_resets")
    record = col.find_one({"token": token})
    if not record:
        return None
    if datetime.now() > datetime.fromisoformat(record["expires"]):
        col.delete_one({"token": token})
        return None
    return record["username"]


def consume_reset_token(token):
    """使用後刪除 token"""
    get_collection("password_resets").delete_one({"token": token})


def update_user_email(username, email):
    """更新使用者 email"""
    get_collection("users").update_one(
        {"username": username},
        {"$set": {"email": email}}
    )


def ensure_default_admin():
    """確保至少有一個 admin 帳號"""
    col = get_collection("users")
    if col.count_documents({}) == 0:
        create_user("admin", "admin", role="admin", display_name="系統管理員")
        print("Default admin created: admin/admin")


def log_action(username, action, detail, ip=""):
    get_collection("admin_worklog").insert_one({
        "user": username,
        "action": action,
        "detail": detail,
        "ip": ip,
        "timestamp": datetime.now().isoformat(),
    })
