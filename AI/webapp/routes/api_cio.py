"""資訊主管儀表板 API"""
import os
import sys
from flask import Blueprint, request, jsonify

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from decorators import login_required
from services import cio_service

bp = Blueprint("api_cio", __name__, url_prefix="/api/cio")


@bp.route("/overview", methods=["GET"])
@login_required
def overview():
    return jsonify({"success": True, "data": cio_service.get_overview()})


@bp.route("/recommendations", methods=["GET"])
@login_required
def recommendations():
    return jsonify({"success": True, "data": cio_service.get_action_recommendations()})


@bp.route("/top-risks", methods=["GET"])
@login_required
def top_risks():
    limit = int(request.args.get("limit", 5))
    return jsonify({"success": True, "data": cio_service.get_top_risk_hosts(limit)})


@bp.route("/health-score", methods=["GET"])
@login_required
def health_score():
    return jsonify({"success": True, "data": cio_service.get_health_score()})


@bp.route("/snapshot", methods=["POST"])
@login_required
def do_snapshot():
    """立刻 snapshot 一次當前合規狀態 (給 cron 或手動觸發)"""
    d = cio_service.snapshot_twgcb_daily()
    return jsonify({"success": True, "data": d})


@bp.route("/trend", methods=["GET"])
@login_required
def trend():
    """?days=30|90|365 — 回歷史合規率陣列"""
    days = int(request.args.get("days", 30))
    return jsonify({"success": True, "data": cio_service.get_compliance_trend(days)})


@bp.route("/trend-chart", methods=["GET"])
@login_required
def trend_chart():
    """PNG 趨勢圖: ?days=30|90|365"""
    from flask import Response
    from services import cio_chart
    days = int(request.args.get("days", 30))
    trend_data = cio_service.get_compliance_trend(days)
    png = cio_chart.render_compliance_trend_png(trend_data, days=days)
    resp = Response(png, mimetype="image/png")
    resp.headers["Cache-Control"] = "public, max-age=300"
    return resp


@bp.route("/aging", methods=["GET"])
@login_required
def aging():
    """合規項老化分析: ?threshold=30 (days)"""
    threshold = int(request.args.get("threshold", 30))
    return jsonify({"success": True, "data": cio_service.get_aging_analysis(threshold)})


@bp.route("/pdf", methods=["GET"])
@login_required
def pdf_report():
    """當月 PDF 報告下載"""
    from flask import Response
    from services import cio_pdf
    from datetime import datetime
    pdf = cio_pdf.build_for_current_month()
    now = datetime.now()
    fname = f"cio_monthly_{now.year}_{now.month:02d}.pdf"
    resp = Response(pdf, mimetype="application/pdf")
    resp.headers["Content-Disposition"] = f"attachment; filename={fname}"
    return resp
