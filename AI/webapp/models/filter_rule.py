"""過濾規則 Model - MongoDB filter_rules collection schema"""

RULE_TYPES = ["keyword", "regex", "level"]

FILTER_RULE_SCHEMA = {
    "rule_id": str,
    "name": str,
    "type": str,           # keyword/regex/level
    "pattern": str,
    "apply_to": str,       # all 或特定 hostname
    "enabled": bool,
    "is_known_issue": bool,
    "known_issue_reason": str,
    "hit_count": int,
    "created_at": str,
    "updated_at": str,
}


def validate_rule(doc):
    """驗證規則文件"""
    if not doc.get("name"):
        raise ValueError("規則名稱不可為空")
    if doc.get("type") not in RULE_TYPES:
        raise ValueError(f"規則類型必須是 {RULE_TYPES} 之一")
    if not doc.get("pattern"):
        raise ValueError("匹配模式不可為空")
    return True
