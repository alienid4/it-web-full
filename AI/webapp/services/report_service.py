"""報告聚合服務"""
from services.mongo_service import get_trend, get_hosts_summary, get_latest_inspections


def get_dashboard_data():
    """取得 Dashboard 所需的所有資料"""
    summary = get_hosts_summary()
    trend = get_trend(7)
    latest = get_latest_inspections()
    return {
        "summary": summary,
        "trend": trend,
        "latest": latest,
        "latest_count": len(latest),
    }
