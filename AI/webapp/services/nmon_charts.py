"""
nmon 月報圖表產生器 (matplotlib → PNG)
- 4 種 metric: cpu / mem / disk / net_kbps
- 快取: data/cache/charts/<hostname>/<YYYY-MM>_<metric>.png
- 失效條件: cache 檔 mtime < nmon_daily 最新 imported_at
"""
import os
import io
from datetime import datetime
import matplotlib
matplotlib.use("Agg")  # 無 X
import matplotlib.pyplot as plt
from matplotlib import rcParams
from matplotlib import font_manager

from services.mongo_service import get_collection
from services import nmon_service

# ---- 找 CJK 字型 ----
_CJK_FONT = None
for candidate in ("Noto Sans CJK TC", "Noto Sans CJK SC", "Noto Sans CJK JP",
                  "WenQuanYi Zen Hei", "WenQuanYi Micro Hei", "DejaVu Sans"):
    try:
        if any(f.name == candidate for f in font_manager.fontManager.ttflist):
            _CJK_FONT = candidate
            break
    except Exception:
        pass
if _CJK_FONT:
    rcParams["font.family"] = _CJK_FONT
rcParams["axes.unicode_minus"] = False

INSPECTION_HOME = os.environ.get("INSPECTION_HOME", "/opt/inspection")
CACHE_DIR = os.path.join(INSPECTION_HOME, "data", "cache", "charts")

METRIC_SPEC = {
    "cpu":      {"title": "CPU 使用率", "unit": "%",    "key": "cpu"},
    "mem":      {"title": "記憶體使用率", "unit": "%", "key": "mem"},
    "disk":     {"title": "磁碟最忙 (%busy)", "unit": "%", "key": "disk"},
    "net_kbps": {"title": "網路吞吐", "unit": " KB/s", "key": "net_kbps"},
}


def _cache_path(hostname, key, metric):
    """key 是唯一字串: YYYY-MM (月) / YYYY-MM-DD (日) / week_YYYY-MM-DD (週起始日)"""
    d = os.path.join(CACHE_DIR, hostname)
    os.makedirs(d, exist_ok=True)
    return os.path.join(d, f"{key}_{metric}.png")


def _latest_import_ts(hostname):
    doc = get_collection("nmon_daily").find_one(
        {"hostname": hostname},
        sort=[("imported_at", -1)],
        projection={"_id": 0, "imported_at": 1},
    )
    if not doc:
        return 0
    try:
        return datetime.strptime(doc["imported_at"], "%Y-%m-%d %H:%M:%S").timestamp()
    except Exception:
        return 0


def _render_series(labels, peaks, avgs, metric, title_suffix, hostname):
    """通用: 一組 (labels, peaks, avgs) 畫成一張圖"""
    spec = METRIC_SPEC[metric]
    unit = spec["unit"]
    title = spec["title"]

    fig, ax = plt.subplots(figsize=(8, 3.2), dpi=110)

    if not labels:
        ax.text(0.5, 0.5, "無資料", ha="center", va="center",
                transform=ax.transAxes, fontsize=14, color="#888")
        ax.set_xticks([]); ax.set_yticks([])
    else:
        ax.plot(range(len(labels)), peaks, color="#E74C3C", linewidth=1.8,
                marker="o", markersize=3, label="峰值")
        ax.fill_between(range(len(labels)), peaks, alpha=0.12, color="#E74C3C")
        if any(v > 0 for v in avgs):
            ax.plot(range(len(labels)), avgs, color="#26A889", linewidth=1.8,
                    marker="o", markersize=3, label="均值")
            ax.fill_between(range(len(labels)), avgs, alpha=0.12, color="#26A889")

        ax.set_ylabel(f"值 ({unit.strip()})", fontsize=10)
        ax.grid(True, linestyle="--", alpha=0.3)
        ax.legend(loc="upper right", fontsize=9, framealpha=0.9)

        n = len(labels)
        step = max(1, n // 12)
        idxs = list(range(0, n, step))
        ax.set_xticks(idxs)
        ax.set_xticklabels([labels[i] for i in idxs], rotation=30, fontsize=8)

        ax.set_ylim(bottom=0)

    ax.set_title(f"{hostname} · {title} · {title_suffix}", fontsize=11, loc="left")
    fig.tight_layout()
    buf = io.BytesIO()
    fig.savefig(buf, format="png", bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    return buf.getvalue()


def _render_month(report, metric, hostname, year, month):
    dailies = report.get("dailies", [])
    key = METRIC_SPEC[metric]["key"]
    labels = [d["date"][-5:] for d in dailies]
    peaks = [(d.get(key) or {}).get("peak") or 0 for d in dailies]
    avgs = [(d.get(key) or {}).get("avg") or 0 for d in dailies]
    return _render_series(labels, peaks, avgs, metric, f"{year}-{month:02d} 月", hostname)


def _render_week(report, metric, hostname):
    dailies = report.get("dailies", [])
    key = METRIC_SPEC[metric]["key"]
    labels = [d["date"][-5:] for d in dailies]
    peaks = [(d.get(key) or {}).get("peak") or 0 for d in dailies]
    avgs = [(d.get(key) or {}).get("avg") or 0 for d in dailies]
    return _render_series(labels, peaks, avgs, metric,
                          f"週 {report.get('start','')} ~ {report.get('end','')}",
                          hostname)


def _render_day(report, metric, hostname, date):
    key = METRIC_SPEC[metric]["key"]
    daily = (report or {}).get("daily") or {}
    ts = daily.get("timeseries") or []
    labels = [pt["time"][:5] for pt in ts]  # HH:MM
    vals = [pt.get(key) or 0 for pt in ts]
    # 日模式只畫一條實際值 (沒有 peak/avg, 就是原始 series)
    return _render_series(labels, vals, [0]*len(vals), metric, f"{date} 日內時序", hostname)


def get_chart_png(hostname, metric, mode="monthly", **kw):
    """
    mode=monthly (year, month)
    mode=weekly  (start: YYYY-MM-DD)
    mode=daily   (date: YYYY-MM-DD)
    """
    if metric not in METRIC_SPEC:
        raise ValueError(f"unknown metric: {metric}")
    force = kw.pop("force", False)

    # key for cache
    if mode == "monthly":
        y, m = kw["year"], kw["month"]
        ck = f"{y:04d}-{m:02d}"
    elif mode == "weekly":
        ck = f"week_{kw['start']}"
    elif mode == "daily":
        ck = f"day_{kw['date']}"
    else:
        raise ValueError(f"unknown mode: {mode}")

    path = _cache_path(hostname, ck, metric)
    latest_ts = _latest_import_ts(hostname)

    if not force and os.path.exists(path):
        cache_ts = os.path.getmtime(path)
        if cache_ts >= latest_ts and os.path.getsize(path) > 100:
            with open(path, "rb") as f:
                return f.read(), True

    # miss → render
    if mode == "monthly":
        report = nmon_service.get_monthly_report(hostname, kw["year"], kw["month"])
        png = _render_month(report, metric, hostname, kw["year"], kw["month"])
    elif mode == "weekly":
        report = nmon_service.get_week_report(hostname, kw["start"])
        png = _render_week(report, metric, hostname)
    else:  # daily
        report = nmon_service.get_day_report(hostname, kw["date"])
        png = _render_day(report, metric, hostname, kw["date"])

    with open(path, "wb") as f:
        f.write(png)
    return png, False


def bust_cache_for_host(hostname):
    """import 完把該主機的 cache 清掉 (下次讀自動重畫)"""
    d = os.path.join(CACHE_DIR, hostname)
    if not os.path.isdir(d):
        return 0
    n = 0
    for f in os.listdir(d):
        if f.endswith(".png"):
            try:
                os.remove(os.path.join(d, f))
                n += 1
            except Exception:
                pass
    return n
