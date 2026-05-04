#!/usr/bin/env python3
"""
verify_nmon.py — v3.17.13.0 對所有勾選 NMON 的主機驗證部署狀態.

四項檢查 (每台主機):
  1. CRON: sudo crontab -l 是否有 nmon 排程
  2. BIN : nmon / topas_nmon binary 是否存在
  3. LOG : /var/log/nmon/ 是否有最近的 .nmon 檔
  4. PROC: 有沒有 nmon process 在跑 (採樣中)

跨表查 nmon_daily collection 算每台「今日筆數」+「最後一筆 date」.

用法:
  INSPECTION_HOME=/opt/inspection python3 verify_nmon.py [--json]
  --json: 輸出 JSON (給 web API 用); 不加: 人讀格式

回傳格式 (JSON):
  {
    "hosts": [
      {hostname, ip, os_group, interval_min, deployed_at, reachable,
       cron_ok, binary_ok, log_ok, proc_ok,
       binary_path, cron_line, log_files,
       daily_today, daily_total, last_sample,
       status: OK|PARTIAL|FAIL|UNREACHABLE, detail}
    ],
    "summary": {total, ok, partial, fail, unreachable}
  }
"""
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timedelta

INSPECTION_HOME = os.environ.get("INSPECTION_HOME") or "/opt/inspection"
sys.path.insert(0, os.path.join(INSPECTION_HOME, "webapp"))

JSON_OUT = "--json" in sys.argv


# 所有檢查合併成一個 shell 命令, 一次連線抓回所有資訊
CHECK_CMD = (
    'echo "=CRON="; sudo crontab -l 2>/dev/null | grep -E "nmon|topas_nmon" | head -3; '
    'echo "=BIN="; (command -v nmon 2>/dev/null || command -v topas_nmon 2>/dev/null || echo NOT_INSTALLED); '
    'echo "=LOG="; ls -lt /var/log/nmon/*.nmon 2>/dev/null | head -3; '
    'echo "=PROC="; pgrep -af "nmon -f" 2>/dev/null | head -3'
)


def run_ansible_check(host_pattern):
    """跑 ansible -m shell, 回 dict[hostname] = raw_text | None"""
    inv = os.path.join(INSPECTION_HOME, "ansible/inventory/hosts.yml")
    if not os.path.exists(inv):
        for p in [
            os.path.join(INSPECTION_HOME, "ansible/inventory/hosts.yaml"),
            os.path.join(INSPECTION_HOME, "ansible/hosts.yml"),
        ]:
            if os.path.exists(p):
                inv = p
                break

    cmd = ["ansible", "-i", inv, host_pattern, "-m", "shell", "-a", CHECK_CMD,
           "-b", "--timeout=15"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    except subprocess.TimeoutExpired:
        return {}

    # ansible (沒 -o) 多行格式:
    #   hostname | CHANGED | rc=0 >>
    #   stdout line 1
    #   stdout line 2
    # (空行)
    #   nexthost | UNREACHABLE | ...
    results = {}
    cur_host = None
    cur_buf = []

    header_re = re.compile(r"^(\S+)\s*\|\s*(SUCCESS|CHANGED|UNREACHABLE|FAILED!?)\s*(?:\|\s*rc=\d+\s*)?(?:>>)?\s*(.*)$")
    for line in r.stdout.splitlines():
        m = header_re.match(line)
        if m:
            if cur_host is not None:
                results[cur_host] = "\n".join(cur_buf).strip()
            cur_host = m.group(1)
            status = m.group(2)
            rest = m.group(3) or ""
            if status in ("UNREACHABLE", "FAILED", "FAILED!"):
                results[cur_host] = None
                cur_host = None
                cur_buf = []
                continue
            cur_buf = [rest] if rest else []
        else:
            if cur_host is not None:
                cur_buf.append(line)
    if cur_host is not None:
        results[cur_host] = "\n".join(cur_buf).strip()

    return results


def parse_check_output(text):
    """把 raw_text 切成 cron / bin / log / proc 4 個 section"""
    sections = {"cron": "", "bin": "", "log": "", "proc": ""}
    cur = None
    for line in text.split("\n"):
        s = line.strip()
        if s == "=CRON=": cur = "cron"; continue
        if s == "=BIN=":  cur = "bin";  continue
        if s == "=LOG=":  cur = "log";  continue
        if s == "=PROC=": cur = "proc"; continue
        if cur and s:
            sections[cur] += s + "\n"
    return sections


def main():
    try:
        from services.mongo_service import get_hosts_col, get_collection
    except Exception as e:
        msg = {"error": f"import mongo_service 失敗: {e}"}
        print(json.dumps(msg) if JSON_OUT else f"[FATAL] {msg['error']}", file=sys.stderr)
        sys.exit(1)

    col = get_hosts_col()
    enabled = list(col.find(
        {"nmon_enabled": True},
        {"_id": 0, "hostname": 1, "ip": 1, "os_group": 1,
         "nmon_interval_min": 1, "nmon_deployed_at": 1}
    ))

    if not enabled:
        out = {"hosts": [], "summary": {"total": 0, "ok": 0, "partial": 0, "fail": 0, "unreachable": 0}}
        if JSON_OUT:
            print(json.dumps(out, ensure_ascii=False))
        else:
            print("[INFO] 沒有勾選 NMON 的主機 (hosts.nmon_enabled=true 為 0 筆)")
        return

    pattern = ":".join([h["hostname"] for h in enabled])
    if not JSON_OUT:
        print(f"[INFO] 檢查 {len(enabled)} 台勾選的主機 (ansible 多執行緒)...", file=sys.stderr)

    raw = run_ansible_check(pattern)

    daily_col = get_collection("nmon_daily")
    today = datetime.now().strftime("%Y-%m-%d")

    results = []
    summary = {"total": len(enabled), "ok": 0, "partial": 0, "fail": 0, "unreachable": 0}

    for h in enabled:
        hostname = h["hostname"]
        text = raw.get(hostname)
        item = {
            "hostname": hostname,
            "ip": h.get("ip", ""),
            "os_group": h.get("os_group", ""),
            "interval_min": h.get("nmon_interval_min"),
            "deployed_at": str(h.get("nmon_deployed_at", "") or ""),
            "reachable": text is not None,
        }

        if text is None:
            item.update({
                "cron_ok": False, "binary_ok": False, "log_ok": False, "proc_ok": False,
                "status": "UNREACHABLE",
                "detail": "ansible 連不上 (SSH/sudo 不通?)",
                "binary_path": "", "cron_line": "", "log_files": [],
                "daily_today": 0, "daily_total": 0, "last_sample": "",
            })
            summary["unreachable"] += 1
            results.append(item)
            continue

        sec = parse_check_output(text)
        bin_line = sec["bin"].strip().split("\n")[0] if sec["bin"].strip() else ""
        cron_ok = bool(sec["cron"].strip()) and "nmon" in sec["cron"].lower()
        binary_ok = bin_line not in ("", "NOT_INSTALLED")
        log_ok = ".nmon" in sec["log"]
        proc_ok = bool(sec["proc"].strip())

        # DB 統計
        daily_today = daily_col.count_documents({"hostname": hostname, "date": today})
        daily_total = daily_col.count_documents({"hostname": hostname})
        last_doc = next(iter(daily_col.find({"hostname": hostname}, {"_id": 0, "date": 1})
                             .sort("date", -1).limit(1)), {})
        last_sample = last_doc.get("date", "")

        item.update({
            "cron_ok": cron_ok,
            "binary_ok": binary_ok,
            "log_ok": log_ok,
            "proc_ok": proc_ok,
            "binary_path": bin_line if binary_ok else "",
            "cron_line": sec["cron"].strip().split("\n")[0] if cron_ok else "",
            "log_files": [l.strip() for l in sec["log"].strip().split("\n")[:3] if l.strip()],
            "daily_today": daily_today,
            "daily_total": daily_total,
            "last_sample": last_sample,
        })

        # 判 status
        if cron_ok and binary_ok:
            if daily_today > 0 or log_ok:
                item["status"] = "OK"
                item["detail"] = ""
                summary["ok"] += 1
            else:
                item["status"] = "PARTIAL"
                item["detail"] = "cron+binary 都在但還沒採樣 (剛部署等下個 cron tick, 通常 5 分鐘內)"
                summary["partial"] += 1
        else:
            item["status"] = "FAIL"
            issues = []
            if not cron_ok:
                issues.append("無 cron 排程")
            if not binary_ok:
                issues.append("nmon binary 沒裝 (公司隔離環境抓不到 EPEL?)")
            item["detail"] = "; ".join(issues)
            summary["fail"] += 1

        results.append(item)

    out = {"hosts": results, "summary": summary}

    if JSON_OUT:
        print(json.dumps(out, ensure_ascii=False, default=str))
    else:
        icon_map = {"OK": "🟢", "PARTIAL": "🟡", "FAIL": "🔴", "UNREACHABLE": "⚫"}
        for r in results:
            icon = icon_map.get(r["status"], "?")
            print(f"{icon} {r['hostname']:25s} cron={'Y' if r['cron_ok'] else 'N'} "
                  f"bin={'Y' if r['binary_ok'] else 'N'} log={'Y' if r['log_ok'] else 'N'} "
                  f"today={r['daily_today']:3d}  {r.get('detail', '')}")
        print(f"\n總計 {summary['total']} 台: "
              f"🟢 {summary['ok']} OK / 🟡 {summary['partial']} 部分 / "
              f"🔴 {summary['fail']} 失敗 / ⚫ {summary['unreachable']} 連不上")


if __name__ == "__main__":
    main()
