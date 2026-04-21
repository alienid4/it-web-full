#!/usr/bin/env python3
# 金融業 IT 每日巡檢 HTML 報告產生器
import sys, os, json, glob, smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from datetime import datetime

INSPECTION_HOME = "/opt/inspection"
SETTINGS_FILE   = os.path.join(INSPECTION_HOME, "data/settings.json")

def load_settings():
    try:
        with open(SETTINGS_FILE, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {}

def load_results(prefix):
    files = sorted(glob.glob(prefix + "_*.json"))
    results = []
    for fp in files:
        try:
            with open(fp, encoding="utf-8") as f:
                results.append(json.load(f))
        except Exception as e:
            print(f"Warning: {fp}: {e}")
    return results

def badge(status):
    cfg = {"ok":("#28a745","#fff","正常"),"warn":("#ffc107","#000","警告"),"error":("#dc3545","#fff","異常")}
    bg, fg, label = cfg.get(status, ("#6c757d","#fff",status))
    return f'<span style="background:{bg};color:{fg};padding:2px 10px;border-radius:12px;font-size:.85em;font-weight:600">{label}</span>'

def disk_bar(pct):
    p = int(float(pct))
    col = "#dc3545" if p >= 90 else "#ffc107" if p >= 80 else "#28a745"
    return (f'<div style="background:#e9ecef;border-radius:4px;height:16px;width:160px">'
            f'<div style="background:{col};width:{p}%;height:16px;border-radius:4px"></div>'
            f'</div><small>{p}%</small>')

def progress_bar(pct, label):
    p = int(float(pct))
    col = "#dc3545" if p >= 90 else "#ffc107" if p >= 70 else "#17a2b8"
    return (f'<div style="margin-bottom:6px"><span style="font-size:.85em;color:#555">{label}</span>'
            f'<div style="background:#e9ecef;border-radius:4px;height:12px">'
            f'<div style="background:{col};width:{p}%;height:12px;border-radius:4px"></div>'
            f'</div><small>{p}%</small></div>')

def build_summary_row(r):
    res = r.get("results", {})
    cells = "".join(
        f'<td style="padding:8px 10px">{badge(res.get(k,{}).get("status","ok"))}</td>'
        for k in ("disk","cpu","service","account","error_log","db")
    )
    return (f'<tr><td style="padding:8px 10px;font-weight:600">{r.get("hostname","")}</td>'
            f'<td style="padding:8px 10px">{r.get("ip","")}</td>'
            f'<td style="padding:8px 10px">{r.get("os","")}</td>'
            f'{cells}'
            f'<td style="padding:8px 10px">{badge(r.get("overall_status","ok"))}</td></tr>')

def build_host_card(r):
    res = r.get("results", {})
    hn  = r.get("hostname","")
    st  = r.get("overall_status","ok")
    bc  = {"ok":"#28a745","warn":"#ffc107","error":"#dc3545"}.get(st,"#6c757d")
    hfg = "#000" if st == "warn" else "#fff"
    th  = 'style="padding:6px;background:#f0f4ff;text-align:left;font-size:.85em"'

    disk = res.get("disk",{})
    disk_rows = ""
    for fs in disk.get("filesystems",[]):
        disk_rows += (f'<tr><td style="padding:5px">{fs.get("mount","")}</td>'
                      f'<td style="padding:5px">{fs.get("size","")}</td>'
                      f'<td style="padding:5px">{fs.get("used","")}</td>'
                      f'<td style="padding:5px">{fs.get("avail","")}</td>'
                      f'<td style="padding:5px">{disk_bar(fs.get("percent",0))}</td>'
                      f'<td style="padding:5px">{badge(fs.get("status","ok"))}</td></tr>')
    if not disk_rows:
        disk_rows = '<tr><td colspan="6" style="padding:5px;color:#888">無資料</td></tr>'

    cpu = res.get("cpu",{})
    cpu_html = progress_bar(cpu.get("cpu_percent",0), "CPU 使用率")
    mem_html = progress_bar(cpu.get("mem_percent",0), "記憶體使用率")

    svc = res.get("service",{})
    svc_rows = ""
    for s in svc.get("services",[]):
        svc_rows += (f'<tr><td style="padding:5px">{s.get("name","")}</td>'
                     f'<td style="padding:5px">{s.get("state","")}</td>'
                     f'<td style="padding:5px">{badge(s.get("status","ok"))}</td></tr>')
    if not svc_rows:
        svc_rows = '<tr><td colspan="3" style="padding:5px;color:#888">無資料</td></tr>'

    acct    = res.get("account",{})
    added   = acct.get("accounts_added",[])
    removed = acct.get("accounts_removed",[])
    acct_html = f'<p style="margin:3px 0">帳號總數：{acct.get("total_accounts","")}</p>'
    if added:   acct_html += f'<p style="color:#dc3545;margin:3px 0">新增：{", ".join(str(x) for x in added)}</p>'
    if removed: acct_html += f'<p style="color:#ffc107;margin:3px 0">刪除：{", ".join(str(x) for x in removed)}</p>'
    if not added and not removed: acct_html += '<p style="color:#28a745;margin:3px 0">無帳號異動</p>'

    el = res.get("error_log",{})
    el_html = (f'<p style="margin:3px 0">來源：{el.get("log_file","")}</p>'
               f'<p style="margin:3px 0">Error：<b style="color:#dc3545">{el.get("error_count",0)}</b> 筆　'
               f'Warning：<b style="color:#ffc107">{el.get("warn_count",0)}</b> 筆</p>')

    db = res.get("db",{})
    db_rows = ""
    for conn in db.get("connections",[]):
        db_rows += (f'<tr><td style="padding:5px">{conn.get("name","")}</td>'
                    f'<td style="padding:5px">{conn.get("host","")}:{conn.get("port","")}</td>'
                    f'<td style="padding:5px">{badge(conn.get("status","ok"))}</td></tr>')
    if not db_rows:
        db_rows = '<tr><td colspan="3" style="padding:5px;color:#888">無設定 DB 連線</td></tr>'

    return f"""
<div style="border:2px solid {bc};border-radius:8px;margin-bottom:24px;overflow:hidden">
  <div style="background:{bc};color:{hfg};padding:10px 16px;font-size:1.05em;font-weight:700">
    {hn} &nbsp; {badge(st)} &nbsp;
    <span style="font-size:.85em;font-weight:400">{r.get("ip","")} | {r.get("os","")}</span>
  </div>
  <div style="padding:16px;display:grid;grid-template-columns:1fr 1fr;gap:16px">
    <div>
      <h4 style="margin:0 0 6px;color:#1a237e">磁碟空間</h4>
      <table style="width:100%;border-collapse:collapse;font-size:.88em">
        <tr><th {th}>掛載點</th><th {th}>大小</th><th {th}>已用</th><th {th}>可用</th><th {th}>使用率</th><th {th}>狀態</th></tr>
        {disk_rows}
      </table>
    </div>
    <div>
      <h4 style="margin:0 0 6px;color:#1a237e">CPU / 記憶體</h4>
      {cpu_html}{mem_html}
      <h4 style="margin:12px 0 6px;color:#1a237e">帳號異動 &amp; 錯誤日誌</h4>
      {acct_html}
      <hr style="border:none;border-top:1px solid #eee;margin:6px 0">
      {el_html}
    </div>
    <div>
      <h4 style="margin:0 0 6px;color:#1a237e">服務狀態</h4>
      <table style="width:100%;border-collapse:collapse;font-size:.88em">
        <tr><th {th}>服務名稱</th><th {th}>狀態值</th><th {th}>結果</th></tr>
        {svc_rows}
      </table>
    </div>
    <div>
      <h4 style="margin:0 0 6px;color:#1a237e">DB 連線</h4>
      <table style="width:100%;border-collapse:collapse;font-size:.88em">
        <tr><th {th}>名稱</th><th {th}>位址</th><th {th}>狀態</th></tr>
        {db_rows}
      </table>
    </div>
  </div>
</div>"""

def generate_html(results, ts):
    total  = len(results)
    n_err  = sum(1 for r in results if r.get("overall_status") == "error")
    n_warn = sum(1 for r in results if r.get("overall_status") == "warn")
    n_ok   = total - n_err - n_warn
    overall = "error" if n_err else "warn" if n_warn else "ok"
    bb  = {"ok":"#28a745","warn":"#ffc107","error":"#dc3545"}[overall]
    bfg = "#000" if overall == "warn" else "#fff"
    btxt= {"ok":"全部主機狀態正常","warn":"部分主機有警告項目","error":"部分主機有異常項目"}[overall]
    try:
        dt_str = datetime.strptime(ts[:15], "%Y%m%d_%H%M%S").strftime("%Y年%m月%d日 %H:%M:%S")
    except Exception:
        dt_str = ts
    summary_rows = "".join(build_summary_row(r) for r in results)
    host_cards   = "".join(build_host_card(r)   for r in results)
    now_str      = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    return f"""<!DOCTYPE html>
<html lang="zh-TW"><head><meta charset="UTF-8">
<title>IT 每日巡檢報告 - {dt_str}</title>
<style>
body{{font-family:"Segoe UI",Arial,sans-serif;margin:0;padding:0;background:#f5f6fa;color:#333}}
.hdr{{background:linear-gradient(135deg,#1a237e,#283593,#1565c0);color:#fff;padding:28px 40px}}
.hdr h1{{margin:0 0 6px;font-size:1.9em}}
.sub{{opacity:.88;font-size:1em}}
.banner{{background:{bb};color:{bfg};padding:10px 40px;font-size:1.1em;font-weight:700}}
.body{{max-width:1440px;margin:0 auto;padding:24px 40px}}
table{{width:100%;border-collapse:collapse}}
th{{background:#1565c0;color:#fff;padding:9px 10px;text-align:left;font-size:.9em}}
tr:nth-child(even){{background:#f8f9fa}}
h2{{color:#1a237e;border-bottom:2px solid #1565c0;padding-bottom:4px;margin-top:32px}}
.footer{{text-align:center;color:#aaa;font-size:.82em;padding:20px 0 32px}}
</style></head><body>
<div class="hdr"><h1>金融業 IT 每日巡檢報告</h1>
<div class="sub">巡檢時間：{dt_str}&nbsp;|&nbsp;主機：{total} 台&nbsp;|&nbsp;正常：{n_ok}&nbsp;警告：{n_warn}&nbsp;異常：{n_err}</div></div>
<div class="banner">{btxt}</div>
<div class="body">
  <h2>巡檢總覽</h2>
  <table style="margin-bottom:28px">
    <tr><th>主機名稱</th><th>IP</th><th>作業系統</th><th>磁碟</th><th>CPU/MEM</th><th>服務</th><th>帳號</th><th>錯誤日誌</th><th>DB連線</th><th>整體狀態</th></tr>
    {summary_rows}
  </table>
  <h2>主機詳細資訊</h2>
  {host_cards}
  <div class="footer">報告產生：{now_str} | 金融業 IT 每日巡檢系統</div>
</div></body></html>"""

def send_email(html, settings, ts, overall):
    cfg = settings.get("notify_email",{})
    if not cfg.get("enabled", False): print("Email disabled."); return
    if overall not in cfg.get("send_on",["error","warn"]): print(f"Skip email: {overall}"); return
    label = {"error":"異常","warn":"警告","ok":"正常"}.get(overall, overall)
    msg = MIMEMultipart("alternative")
    msg["Subject"] = f"[IT巡檢] {ts[:8]} 巡檢報告 - {label}"
    msg["From"] = cfg.get("from","")
    msg["To"]   = ", ".join(cfg.get("to",[]))
    msg.attach(MIMEText(html, "html", "utf-8"))
    try:
        srv = smtplib.SMTP(cfg["smtp_host"], cfg.get("smtp_port",587))
        if cfg.get("smtp_tls", True): srv.starttls()
        if cfg.get("smtp_user"): srv.login(cfg["smtp_user"], cfg.get("smtp_pass",""))
        srv.sendmail(msg["From"], cfg.get("to",[]), msg.as_string())
        srv.quit()
        print(f"Email sent to: {msg['To']}")
    except Exception as e:
        print(f"Email failed: {e}")

def main():
    if len(sys.argv) < 2:
        print("Usage: generate_report.py <prefix>"); sys.exit(1)
    prefix  = sys.argv[1]
    ts      = os.path.basename(prefix)
    results = load_results(prefix)
    if not results:
        print(f"No JSON: {prefix}_*.json"); sys.exit(1)
    print(f"Loaded {len(results)} host(s)")
    settings = load_settings()
    html     = generate_html(results, ts)
    out_path = prefix + "_report.html"
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Report: {out_path}")
    overall = "ok"
    for r in results:
        s = r.get("overall_status","ok")
        if s == "error": overall = "error"; break
        if s == "warn" and overall != "error": overall = "warn"
    send_email(html, settings, ts, overall)

if __name__ == "__main__":
    main()
