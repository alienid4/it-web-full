"""CIO 月度 PDF 報告產製 (reportlab)"""
import io
import os
from datetime import datetime
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import cm, mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle,
                                 PageBreak, Image)
from reportlab.lib.enums import TA_CENTER, TA_LEFT

# 註冊 CJK 字型
_CJK_FONT_PATHS = [
    "/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/google-noto-sans-cjk-ttc-fonts/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",
]
_FONT_NAME = "Helvetica"
for p in _CJK_FONT_PATHS:
    if os.path.exists(p):
        try:
            pdfmetrics.registerFont(TTFont("NotoCJK", p, subfontIndex=0))
            _FONT_NAME = "NotoCJK"
            break
        except Exception:
            continue


def _styles():
    ss = getSampleStyleSheet()
    return {
        "title": ParagraphStyle("title", parent=ss["Title"], fontName=_FONT_NAME, fontSize=20, leading=26, alignment=TA_CENTER, spaceAfter=6),
        "subtitle": ParagraphStyle("subtitle", parent=ss["Normal"], fontName=_FONT_NAME, fontSize=11, textColor=colors.grey, alignment=TA_CENTER, spaceAfter=18),
        "h2": ParagraphStyle("h2", parent=ss["Heading2"], fontName=_FONT_NAME, fontSize=14, textColor=colors.HexColor("#26A889"), spaceBefore=10, spaceAfter=6),
        "normal": ParagraphStyle("n", parent=ss["Normal"], fontName=_FONT_NAME, fontSize=10, leading=14),
        "small": ParagraphStyle("s", parent=ss["Normal"], fontName=_FONT_NAME, fontSize=8, textColor=colors.grey),
    }


def build_monthly_pdf(year, month, data):
    """
    data = {
        "health_score": {...},
        "compliance": {...},
        "top_risks": [...],
        "aging": {...},
        "trend_png": bytes or None,
    }
    回 PDF bytes
    """
    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4,
                            leftMargin=20*mm, rightMargin=20*mm,
                            topMargin=18*mm, bottomMargin=18*mm)
    st = _styles()
    story = []

    # Header
    story.append(Paragraph(f"IT 監控系統 — {year} 年 {month} 月 月報", st["title"]))
    story.append(Paragraph(f"產製時間: {datetime.now().strftime('%Y-%m-%d %H:%M')}", st["subtitle"]))

    # 綜合健康指數
    hs = data.get("health_score", {})
    story.append(Paragraph("一、綜合健康指數", st["h2"]))
    score_tbl = Table([
        ["總分", f"{hs.get('score', 0):.0f} / 100", f"等級: {hs.get('level', '-')}"],
        ["主機健康", f"{hs.get('components', {}).get('host_health', 0):.0f}%", ""],
        ["TWGCB 合規", f"{hs.get('components', {}).get('compliance', 0):.0f}%", ""],
        ["資安評分", f"{hs.get('components', {}).get('security', 0):.0f}%", ""],
    ], colWidths=[4*cm, 4*cm, 8*cm])
    score_tbl.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (-1, -1), _FONT_NAME),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#E8F5E9")),
        ("TEXTCOLOR", (1, 0), (1, 0), colors.HexColor("#26A889")),
        ("FONTSIZE", (1, 0), (1, 0), 16),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.lightgrey),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ]))
    story.append(score_tbl)
    story.append(Spacer(1, 10))

    # TWGCB 合規率
    cc = data.get("compliance", {})
    story.append(Paragraph("二、TWGCB 合規率", st["h2"]))
    cc_tbl = Table([
        ["總檢查項", str(cc.get("total_checks", 0))],
        ["通過", str(cc.get("pass_checks", 0))],
        ["失敗", str(cc.get("fail_checks", 0))],
        ["例外", str(cc.get("exception_count", 0))],
        ["通過率", f"{cc.get('rate', 0):.1f}%"],
    ], colWidths=[6*cm, 10*cm])
    cc_tbl.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (-1, -1), _FONT_NAME),
        ("FONTSIZE", (0, 0), (-1, -1), 10),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.lightgrey),
        ("BACKGROUND", (0, 4), (-1, 4), colors.HexColor("#FFF8E1")),
        ("FONTSIZE", (1, 4), (1, 4), 14),
    ]))
    story.append(cc_tbl)

    # 趨勢圖 (PNG)
    if data.get("trend_png"):
        story.append(Spacer(1, 10))
        img = Image(io.BytesIO(data["trend_png"]), width=17*cm, height=6*cm)
        story.append(img)

    # Top 5 高風險主機
    story.append(Paragraph("三、Top 5 高風險主機", st["h2"]))
    risks = data.get("top_risks", [])
    if risks:
        rows = [["#", "主機", "OS", "合規率", "Pass/Total", "失敗"]]
        for i, h in enumerate(risks, 1):
            rows.append([str(i), h["hostname"], (h.get("os") or "-")[:20],
                         f"{h['rate']:.1f}%", f"{h['pass']}/{h['total']}", str(h["fail"])])
        t = Table(rows, colWidths=[0.8*cm, 4.5*cm, 3.5*cm, 2.5*cm, 2.5*cm, 2*cm])
        t.setStyle(TableStyle([
            ("FONTNAME", (0, 0), (-1, -1), _FONT_NAME),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F0FAF0")),
            ("GRID", (0, 0), (-1, -1), 0.3, colors.lightgrey),
            ("ALIGN", (3, 0), (-1, -1), "RIGHT"),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ]))
        story.append(t)
    else:
        story.append(Paragraph("✓ 所有主機合規率 100%", st["normal"]))

    # 老化分析
    story.append(Spacer(1, 10))
    story.append(Paragraph("四、合規項老化分析 (30 天門檻)", st["h2"]))
    ag = data.get("aging", {})
    story.append(Paragraph(
        f"總 FAIL 項: <b>{ag.get('total_fails', 0)}</b>, 超過 30 天未修: <b>{ag.get('over_threshold_count', 0)}</b>",
        st["normal"]))
    if ag.get("by_department"):
        story.append(Spacer(1, 4))
        rows = [["部門", "FAIL 數", "主機數"]]
        for v in ag["by_department"][:10]:
            rows.append([v.get("department") or "(未分類)", str(v["fail_count"]), str(v["host_count"])])
        t = Table(rows, colWidths=[7*cm, 3*cm, 3*cm])
        t.setStyle(TableStyle([
            ("FONTNAME", (0, 0), (-1, -1), _FONT_NAME),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#F0FAF0")),
            ("GRID", (0, 0), (-1, -1), 0.3, colors.lightgrey),
            ("ALIGN", (1, 0), (-1, -1), "RIGHT"),
        ]))
        story.append(t)

    # 建議行動
    story.append(Spacer(1, 12))
    story.append(Paragraph("五、本期建議行動", st["h2"]))
    recs = data.get("recommendations", [])
    if recs:
        for r in recs:
            icon = {"error": "🔴", "warn": "🟠", "info": "ℹ️", "ok": "✅"}.get(r.get("level"), "•")
            story.append(Paragraph(f"{icon} {r.get('text', '')}", st["normal"]))
            story.append(Spacer(1, 3))
    else:
        story.append(Paragraph("系統目前無重大風險。", st["normal"]))

    # Footer
    story.append(Spacer(1, 20))
    story.append(Paragraph("—— 本報告由 IT 監控系統自動產製 ——", st["small"]))

    doc.build(story)
    buf.seek(0)
    return buf.getvalue()


def build_for_current_month():
    """抓當月資料, 產 PDF"""
    from services import cio_service, cio_chart
    now = datetime.now()
    trend_png = cio_chart.render_compliance_trend_png(
        cio_service.get_compliance_trend(30), days=30
    )
    data = {
        "health_score": cio_service.get_health_score(),
        "compliance": {k: v for k, v in cio_service.get_twgcb_compliance().items() if k != "host_rates"},
        "top_risks": cio_service.get_top_risk_hosts(5),
        "aging": cio_service.get_aging_analysis(30),
        "trend_png": trend_png,
        "recommendations": cio_service.get_action_recommendations(),
    }
    return build_monthly_pdf(now.year, now.month, data)
