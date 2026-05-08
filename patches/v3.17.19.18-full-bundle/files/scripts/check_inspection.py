#!/usr/bin/env python3
"""巡檢健康診斷 - 一秒看出 inspection 是否異常
Usage: python3 /seclog/AI/inspection/scripts/check_inspection.py
"""
import sys, os, json
from datetime import datetime, timedelta
sys.path.insert(0, '/seclog/AI/inspection/webapp')
os.environ.setdefault('INSPECTION_HOME', '/seclog/AI/inspection')

from services.mongo_service import get_collection

def main():
    today = datetime.now().strftime('%Y-%m-%d')
    yesterday = (datetime.now() - timedelta(days=1)).strftime('%Y-%m-%d')

    print('=' * 70)
    print(f'巡檢健康檢查  ({datetime.now().strftime("%Y-%m-%d %H:%M:%S")})')
    print('=' * 70)

    # 1. 主機表
    hosts = list(get_collection('hosts').find({}, {'_id': 0}))
    bare_ip = [h for h in hosts if h.get('hostname', '').replace('.', '').isdigit()]
    no_os = [h for h in hosts if not h.get('os_group')]

    print(f'\n[主機表] 共 {len(hosts)} 台')
    if bare_ip:
        print(f'  ⚠ 裸 IP 沒 hostname: {len(bare_ip)} 台 → {[h["hostname"] for h in bare_ip]}')
    if no_os:
        print(f'  ⚠ 沒 os_group:      {len(no_os)} 台 → {[h["hostname"] for h in no_os]}')
    if not bare_ip and not no_os:
        print(f'  ✓ 全部 hostname/OS 完整')

    # 2. 今日巡檢
    insp = get_collection('inspections')
    today_count = insp.count_documents({'run_date': today})
    yesterday_count = insp.count_documents({'run_date': yesterday})

    print(f'\n[今日巡檢] {today}')
    if today_count == 0:
        print(f'  ✗ 今天沒任何巡檢記錄!')
        if yesterday_count > 0:
            print(f'    昨天 {yesterday} 有 {yesterday_count} 筆 → cron 沒跑或當掉')
        print(f'  → 修法: sudo bash /seclog/AI/inspection/run_inspection.sh')
    else:
        print(f'  ✓ {today_count} 筆')
        # 列出哪些主機今天有巡檢
        today_hosts = insp.distinct('hostname', {'run_date': today})
        # 跳過 skip=true 的主機 (例如 Windows 暫不支援)
        non_skip_hosts = set(h['hostname'] for h in hosts if not h.get('skip', False))
        # 從 inventory 讀 skip 標記
        skipped_hosts = set()
        try:
            import yaml as _yaml
            inv_path = os.path.join(os.environ['INSPECTION_HOME'], 'ansible/inventory/hosts.yml')
            with open(inv_path) as _f:
                inv = _yaml.safe_load(_f)
            def _walk(node):
                if isinstance(node, dict):
                    if 'hosts' in node:
                        for hn, hv in (node['hosts'] or {}).items():
                            if hv and hv.get('skip'):
                                skipped_hosts.add(hn)
                    if 'children' in node:
                        for cn, cv in (node['children'] or {}).items():
                            _walk(cv)
            _walk(inv.get('all', {}))
        except Exception:
            pass
        host_set = set(h['hostname'] for h in hosts) - skipped_hosts
        missing = host_set - set(today_hosts)
        extra = set(today_hosts) - host_set - skipped_hosts
        if skipped_hosts:
            print(f'  ℹ 設計跳過 (skip=true): {sorted(skipped_hosts)}')
        if missing:
            print(f'  ⚠ 主機表有但今日沒巡檢: {sorted(missing)}')
        if extra:
            print(f'  ⚠ 今日有巡檢但不在主機表 (孤兒): {sorted(extra)}')
        # status 分布
        for status in ['ok', 'warn', 'error']:
            n = insp.count_documents({'run_date': today, 'overall_status': status})
            if n > 0:
                icon = {'ok':'✓','warn':'⚠','error':'✗'}[status]
                print(f'  {icon} {status:6s}: {n} 台')

    # 3. 巡檢資料品質
    bad_date = insp.count_documents({'run_date': {'$not': {'$regex': '^20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'}}})
    if bad_date > 0:
        print(f'\n[資料品質]')
        print(f'  ⚠ {bad_date} 筆 inspection run_date 格式異常 (壞資料)')
        print(f'  → 清理: db.inspections.deleteMany({{run_date: {{$not: {{$regex: "^20[0-9][0-9]-"}}}}}})')

    # 4. 報告檔案 vs DB 一致性
    report_dir = '/seclog/AI/inspection/data/reports'
    today_reports = []
    if os.path.exists(report_dir):
        prefix = today.replace('-', '')
        today_reports = [f for f in os.listdir(report_dir) if f.startswith(prefix) and f.endswith('.json')]

    print(f'\n[報告檔案 vs MongoDB]')
    print(f'  今日 JSON 檔: {len(today_reports)} 個')
    print(f'  今日 DB 記錄: {today_count} 筆')
    if len(today_reports) > 0 and today_count == 0:
        print(f'  ✗ 有檔案但沒匯入 DB → 跑 seed_data.py')
        print(f'    cd /seclog/AI/inspection/webapp && python3 seed_data.py')
    elif len(today_reports) > today_count:
        print(f'  ⚠ 檔案比 DB 多 → seed_data.py 可能漏跑')

    # 5. Cron 狀態
    print(f'\n[Cron 排程]')
    try:
        import subprocess
        r = subprocess.run(['crontab', '-l'], capture_output=True, text=True, timeout=5,
                          env={**os.environ, 'USER': 'root'})
        if 'run_inspection' in r.stdout:
            for line in r.stdout.splitlines():
                if 'run_inspection' in line and not line.strip().startswith('#'):
                    print(f'  ✓ {line.strip()}')
        else:
            print(f'  ⚠ root crontab 沒有 run_inspection.sh')
    except Exception as e:
        print(f'  ⚠ 無法讀 crontab: {e}')

    # 6. 最近 log
    log_dir = '/seclog/AI/inspection/logs'
    if os.path.exists(log_dir):
        logs = sorted([f for f in os.listdir(log_dir) if f.endswith('_run.log')], reverse=True)
        if logs:
            latest = logs[0]
            log_path = os.path.join(log_dir, latest)
            mtime = datetime.fromtimestamp(os.path.getmtime(log_path))
            age_hours = (datetime.now() - mtime).total_seconds() / 3600
            print(f'\n[最近巡檢 log]')
            print(f'  {latest}  ({age_hours:.1f} 小時前)')
            if age_hours > 25:
                print(f'  ⚠ 超過 25 小時沒新 log → 排程可能掛了')

    print()
    print('=' * 70)
    print('Done. 如果全部 ✓ 就沒事，看到 ✗ 或 ⚠ 對症處理。')

if __name__ == '__main__':
    main()
