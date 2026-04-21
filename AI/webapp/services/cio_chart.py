"""CIO 合規趨勢圖 (matplotlib PNG)"""
import io, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import rcParams, font_manager

_CJK_FONT = None
for candidate in ("Noto Sans CJK TC", "Noto Sans CJK SC", "Noto Sans CJK JP", "DejaVu Sans"):
    if any(f.name == candidate for f in font_manager.fontManager.ttflist):
        _CJK_FONT = candidate; break
if _CJK_FONT:
    rcParams["font.family"] = _CJK_FONT
rcParams["axes.unicode_minus"] = False


def render_compliance_trend_png(trend_data, days=30):
    """trend_data = [{date, rate, ...}]"""
    fig, ax = plt.subplots(figsize=(10, 3.6), dpi=110)
    if not trend_data:
        ax.text(0.5, 0.5, "尚無趨勢資料 (需每日 snapshot 累積)", ha="center", va="center",
                transform=ax.transAxes, fontsize=12, color="#888")
        ax.set_xticks([]); ax.set_yticks([])
    else:
        labels = [d["date"][-5:] for d in trend_data]
        rates = [d.get("rate", 0) for d in trend_data]
        ax.plot(range(len(labels)), rates, color="#26A889", linewidth=2,
                marker="o", markersize=4, label="合規率")
        ax.fill_between(range(len(labels)), rates, alpha=0.15, color="#26A889")
        # 95% 目標線
        ax.axhline(95, color="#f5a623", linestyle="--", linewidth=1, alpha=0.7, label="目標 95%")
        ax.set_ylabel("合規率 (%)", fontsize=10)
        ax.set_ylim(max(0, min(rates)-10), 100.5)
        ax.legend(loc="lower right", fontsize=9)
        ax.grid(True, linestyle="--", alpha=0.3)
        n = len(labels)
        step = max(1, n // 12)
        idxs = list(range(0, n, step))
        ax.set_xticks(idxs)
        ax.set_xticklabels([labels[i] for i in idxs], rotation=30, fontsize=8)
    ax.set_title(f"TWGCB 合規率趨勢 — 近 {days} 天", fontsize=11, loc="left")
    fig.tight_layout()
    buf = io.BytesIO()
    fig.savefig(buf, format="png", bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    return buf.getvalue()
