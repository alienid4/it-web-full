"""主機 Model - MongoDB hosts collection schema"""

HOST_SCHEMA = {
    "hostname": str,       # 主機名稱
    "ip": str,             # IP 位址
    "os": str,             # 作業系統
    "os_group": str,       # OS 群組 (rhel/debian/rocky/aix)
    "status": str,         # 使用中/停用
    "environment": str,    # 正式/測試
    "group": str,          # 自訂群組
    "has_python": bool,    # 是否有 Python
    "asset_seq": str,      # 資產編號
    "asset_name": str,     # 資產名稱
    "division": str,       # 處
    "department": str,     # 部
    "owner": str,          # 負責單位
    "custodian": str,      # 保管者
    "custodian_ad": str,   # 保管者 AD 帳號
    "imported_at": str,    # 匯入時間
    "updated_at": str,     # 更新時間
}


def validate_host(doc):
    """驗證主機文件基本欄位"""
    required = ["hostname", "ip"]
    for field in required:
        if field not in doc:
            raise ValueError(f"缺少必要欄位: {field}")
    return True
