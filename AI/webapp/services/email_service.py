"""Email 寄信服務"""
import smtplib
import os
import json
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from config import SETTINGS_FILE


def _get_smtp_config():
    """從 settings.json 讀取 SMTP 設定"""
    with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
        settings = json.load(f)
    cfg = settings.get("notify_email", {})
    if not cfg.get("enabled"):
        return None
    # 密碼支援環境變數
    pwd = cfg.get("smtp_pass", "")
    if pwd.startswith("ENV:"):
        pwd = os.environ.get(pwd[4:], "")
    cfg["smtp_pass"] = pwd
    return cfg


def send_email(to, subject, body_html):
    """寄送 HTML 郵件

    Args:
        to: 收件人 email (str)
        subject: 主旨 (str)
        body_html: HTML 內容 (str)

    Returns:
        True if sent, raises Exception on failure
    """
    cfg = _get_smtp_config()
    if not cfg:
        raise Exception("Email 未啟用，請在系統管理 > Email 設定中設定 SMTP")

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = cfg.get("from", cfg.get("smtp_user", ""))
    msg["To"] = to

    msg.attach(MIMEText(body_html, "html", "utf-8"))

    with smtplib.SMTP(cfg["smtp_host"], cfg.get("smtp_port", 587), timeout=10) as server:
        if cfg.get("smtp_tls", True):
            server.starttls()
        if cfg.get("smtp_user") and cfg.get("smtp_pass"):
            server.login(cfg["smtp_user"], cfg["smtp_pass"])
        server.sendmail(msg["From"], [to], msg.as_string())

    return True
