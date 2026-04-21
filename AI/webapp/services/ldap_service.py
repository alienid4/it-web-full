"""LDAP 查詢服務 - Mock 模式（待 IT 部門提供實際 LDAP 設定）"""
import time
from config import LDAP_CONFIG

_cache = {}


def query_user(ad_account):
    """查詢 AD 人員資訊，目前為 Mock 模式"""
    now = time.time()
    if ad_account in _cache:
        entry, ts = _cache[ad_account]
        if now - ts < LDAP_CONFIG.get("cache_ttl", 3600):
            return entry

    # Mock 回傳
    result = {
        "ad_account": ad_account,
        "display_name": f"Mock User ({ad_account})",
        "department": "資訊管理處",
        "title": "系統工程師",
        "email": f"{ad_account}@company.com",
        "phone": "1234",
        "source": "mock",
    }
    _cache[ad_account] = (result, now)
    return result
