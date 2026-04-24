#!/usr/bin/env python3
# v3.12.0.0 W1: mock data source，家裡 221 開發用
# 取代真 vCenter，為真 collector 還沒寫完前提供畫面資料
# 之後 W1 會寫 vcenter_collector.py 接真 vCenter，讀 MongoDB 快照

from datetime import datetime, timedelta


def get_overview_data(now=None):
    now = now or datetime.now()
    last = now.replace(minute=0, second=0, microsecond=0) - timedelta(hours=now.hour % 8)
    nxt = last + timedelta(hours=8)

    return {
        "last_fetch": last.strftime("%Y-%m-%d %H:%M"),
        "next_fetch": nxt.strftime("%Y-%m-%d %H:%M"),
        "mock_mode": True,

        "total_hosts": 73,
        "total_clusters": 14,
        "warn_clusters": 1,
        "eos_hosts": 22,
        "hw_events": 0,
        "status_overall": "ok",

        "report_available": {
            "month": "2026-03",
            "generated": "2026-04-01 03:00",
            "pages": 6,
            "size": "2.1 MB",
            "has_pdf": True,
        },
        "next_report_date": "2026-05-01",

        "locations": [
            {"name": "板橋", "esxi_count": 38, "clusters": [
                {"name": "BQ_PROD_A", "status": "ok", "tag": None},
                {"name": "BQ_PROD_B", "status": "ok", "tag": None},
                {"name": "BQ_PROD_Cluster01", "status": "warn", "tag": "EOS"},
                {"name": "BQ_PROD_Cluster02", "status": "warn", "tag": "EOS · CPU 82%"},
                {"name": "BQ_PROD_LOG", "status": "ok", "tag": None},
            ], "ok_count": 3, "total_count": 5},
            {"name": "內湖", "esxi_count": 24, "clusters": [
                {"name": "NH_PROD_01", "status": "ok", "tag": None},
                {"name": "NH_PROD_02", "status": "ok", "tag": None},
                {"name": "NH_PROD_UAT", "status": "warn", "tag": "EOS"},
                {"name": "NH_PROD_vSAN", "status": "warn", "tag": "EOS"},
                {"name": "NH_UAT_vSAN", "status": "warn", "tag": "EOS"},
                {"name": "VCF_Prod_vSAN", "status": "ok", "tag": None},
            ], "ok_count": 3, "total_count": 6},
            {"name": "敦南", "esxi_count": 10, "clusters": [
                {"name": "DN_PROD", "status": "ok", "tag": None},
                {"name": "DN_UAT", "status": "ok", "tag": "測試"},
            ], "ok_count": 2, "total_count": 2},
        ],

        "risks": [
            {
                "title": "22 台 ESXi 跑 EOS 版本",
                "desc": "vSphere 7.0 2025-10 已 EOL · 金管會稽核可能列點 · Q3 前完成升級",
                "level": "danger",
            },
            {
                "title": "BQ_PROD_Cluster02 CPU 連續 14 天 > 80%",
                "desc": "與 job 排程相關 · 建議下季評估擴容 · Owner 王OO",
                "level": "warn",
            },
            {
                "title": "內湖 vSAN 容量 82%",
                "desc": "預估 6 個月後滿載 · 已納入 Q3 擴容計畫",
                "level": "info",
            },
        ],

        "vcenters": [
            {"name": "板橋", "host": "10.93.x.x", "status": "live", "version": "8.0.3"},
            {"name": "內湖-1", "host": "10.93.x.x", "status": "pending", "version": None},
            {"name": "內湖-2", "host": "10.93.x.x", "status": "pending", "version": None},
            {"name": "VCF", "host": "10.93.x.x", "status": "pending", "version": None},
            {"name": "敦南", "host": "10.93.x.x", "status": "pending", "version": None},
        ],
    }
