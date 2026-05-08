#!/usr/bin/env python3
"""v3.17.19.8 端到端 dashboard 驗證 (含 ping-all 主管儀表板)"""
import sys, time, json
sys.path.insert(0, '/seclog/AI/inspection/webapp')
import os
os.environ['INSPECTION_HOME'] = '/seclog/AI/inspection'

def main():
    from app import app
    client = app.test_client()
    with client.session_transaction() as s:
        s['user_id'] = 'superadmin_smoke'
        s['username'] = 'superadmin_smoke'
        s['role'] = 'superadmin'
    SLOW_MS = 800
    checks = [
        ('/api/admin/me', 'admin me'),
        ('/api/admin/system/status', 'dashboard 系統狀態'),
        ('/api/admin/system/info', 'dashboard 系統資訊'),
        ('/api/admin/online-users', '在線使用者'),
        ('/api/admin/settings', '設定'),
        ('/api/hosts', '主機列表'),
        ('/api/admin/hosts/ping-all', 'ping-all (主管儀表板)'),
        ('/api/inspections/latest', '今日報告'),
        ('/api/admin/health-check', '健康檢查'),
        ('/api/settings/version', '版本'),
    ]
    results = []
    for path, label in checks:
        t0 = time.time()
        try:
            r = client.get(path)
            elapsed = (time.time() - t0) * 1000
            body = r.get_data(as_text=True)
            fail = None
            if r.status_code != 200:
                fail = f'HTTP {r.status_code}'
            else:
                try:
                    j = json.loads(body)
                    if isinstance(j, dict):
                        if j.get('success') is False:
                            fail = 'success=false: ' + str(j.get('error', '?'))[:80]
                        elif j.get('error'):
                            fail = 'has error: ' + str(j.get('error'))[:80]
                        elif not (j.get('success') is True or 'data' in j or len(j) > 0):
                            fail = 'empty response'
                    elif not isinstance(j, list):
                        fail = 'unexpected JSON type'
                except Exception as e:
                    fail = 'JSON parse error: ' + str(e)[:80]
            results.append({'path': path, 'label': label, 'fail': fail, 'ms': elapsed})
        except Exception as e:
            results.append({'path': path, 'label': label, 'fail': 'EXCEPTION: ' + str(e), 'ms': (time.time()-t0)*1000})
    print('=' * 75)
    print('DASHBOARD SMOKE TEST')
    print('=' * 75)
    failed = 0; slow = 0
    for r in results:
        icon = '✗' if r['fail'] else ('⚠' if r['ms'] > SLOW_MS else '✓')
        ms_str = f'{r["ms"]:8.1f}ms'
        print(f'{icon} {ms_str}  {r["label"]:25s} {r["path"]}')
        if r['fail']:
            print(f'     └─ {r["fail"]}'); failed += 1
        elif r['ms'] > SLOW_MS: slow += 1
    print('=' * 75)
    print(f'Result: {len(results)-failed}/{len(results)} PASS  | {slow} SLOW (>800ms) | {failed} FAIL')
    return 0 if failed == 0 else 1
if __name__ == '__main__':
    sys.exit(main())
