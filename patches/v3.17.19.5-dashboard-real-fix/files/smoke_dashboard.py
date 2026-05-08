#!/usr/bin/env python3
"""v3.17.19.5 真正端到端 dashboard 驗證腳本。
每次部署後自動跑，抓「卡片載入中卡住」這類隱形 bug。
"""
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

    SLOW_MS = 800     # warning threshold
    BUDGET_MS = 100   # warm cache should be < 100ms
    
    # endpoints + 必備欄位驗證
    checks = [
        ('/api/admin/me', None, 'admin me'),
        ('/api/admin/system/status', ['data', 'flask', 'mongodb', 'disk', 'containers'], 'dashboard 系統狀態'),
        ('/api/admin/system/info', ['data', 'os', 'hostname', 'ip', 'python'], 'dashboard 系統資訊'),
        ('/api/admin/online-users', ['data', 'online_count', 'total'], '在線使用者'),
        ('/api/admin/settings', ['data'], '設定'),
        ('/api/hosts', ['data'], '主機列表'),
        ('/api/admin/health-check', ['checks', 'all_ok'], '健康檢查'),
        ('/api/settings/version', ['data'], '版本'),
    ]

    results = []
    for path, must_have, label in checks:
        t0 = time.time()
        try:
            r = client.get(path)
            elapsed = (time.time() - t0) * 1000
            body = r.get_data(as_text=True)
            try:
                j = json.loads(body)
            except Exception as e:
                results.append({'path': path, 'label': label, 'fail': 'JSON parse error: ' + str(e), 'ms': elapsed})
                continue
            if r.status_code != 200:
                results.append({'path': path, 'label': label, 'fail': f'HTTP {r.status_code}', 'ms': elapsed})
                continue
            if not j.get('success'):
                results.append({'path': path, 'label': label, 'fail': 'success!=true: ' + str(j.get('error', '?'))[:80], 'ms': elapsed})
                continue
            if must_have:
                top_key = must_have[0]
                if top_key not in j:
                    results.append({'path': path, 'label': label, 'fail': f'missing key: {top_key}', 'ms': elapsed})
                    continue
                # if data is dict, check sub-keys
                top_val = j.get(top_key)
                if isinstance(top_val, dict):
                    missing = [k for k in must_have[1:] if k not in top_val]
                    if missing:
                        results.append({'path': path, 'label': label, 'fail': f'data missing keys: {missing}', 'ms': elapsed})
                        continue
            results.append({'path': path, 'label': label, 'fail': None, 'ms': elapsed})
        except Exception as e:
            results.append({'path': path, 'label': label, 'fail': 'EXCEPTION: ' + str(e), 'ms': (time.time()-t0)*1000})

    print('=' * 70)
    print('DASHBOARD SMOKE TEST')
    print('=' * 70)
    failed = 0
    slow = 0
    for r in results:
        icon = '✗' if r['fail'] else ('⚠' if r['ms'] > SLOW_MS else '✓')
        ms_str = f'{r["ms"]:7.1f}ms'
        print(f'{icon} {ms_str}  {r["label"]:20s} {r["path"]}')
        if r['fail']:
            print(f'     └─ {r["fail"]}')
            failed += 1
        elif r['ms'] > SLOW_MS:
            slow += 1
    print('=' * 70)
    print(f'Result: {len(results)-failed}/{len(results)} PASS  | {slow} SLOW (>800ms) | {failed} FAIL')
    
    return 0 if failed == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
