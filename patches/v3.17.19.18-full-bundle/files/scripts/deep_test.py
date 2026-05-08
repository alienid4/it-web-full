#!/usr/bin/env python3
"""v3.17.19.x 深度測試 - 掃所有 page / API / 主流程 / 資料完整性"""
import sys, time, json, os
sys.path.insert(0, '/seclog/AI/inspection/webapp')
os.environ['INSPECTION_HOME'] = '/seclog/AI/inspection'

results = {'pass': [], 'fail': [], 'warn': []}

def section(title):
    print()
    print('=' * 75)
    print(title)
    print('=' * 75)

def test(label, ok, detail='', warn=False):
    icon = '✓' if ok else ('⚠' if warn else '✗')
    bucket = 'pass' if ok else ('warn' if warn else 'fail')
    msg = icon + ' ' + label + (' [' + detail + ']' if detail else '')
    print(msg)
    results[bucket].append({'label': label, 'detail': detail})

def main():
    from app import app
    client = app.test_client()
    with client.session_transaction() as s:
        s['user_id']='deep_test'; s['username']='deep_test'; s['role']='superadmin'

    section('1. 頁面渲染 (HTML pages)')
    pages = [
        ('/login', 'login'),
        ('/admin', 'admin'),
        ('/', 'home'),
        ('/report', 'report'),
    ]
    for path, label in pages:
        try:
            r = client.get(path)
            ok = r.status_code in (200, 302)
            size_kb = len(r.get_data())/1024
            test(label + ' ' + path, ok, 'HTTP ' + str(r.status_code) + ', ' + str(int(size_kb)) + 'KB')
        except Exception as e:
            test(label + ' ' + path, False, str(e)[:80])

    section('2. 主要 API endpoint')
    apis = [
        ('/api/admin/me', 'admin auth'),
        ('/api/admin/system/status', 'sys status'),
        ('/api/admin/system/info', 'sys info'),
        ('/api/admin/online-users', 'online users'),
        ('/api/admin/settings', 'settings'),
        ('/api/admin/health-check', 'health-check'),
        ('/api/settings/version', 'version'),
        ('/api/hosts', 'hosts list'),
        ('/api/hosts/summary', 'hosts summary'),
        ('/api/admin/hosts/ping-all', 'ping-all'),
        ('/api/inspections/latest', 'inspections'),
        ('/api/admin/audit/accounts', 'audit accounts'),
        ('/api/admin/audit/hr', 'audit hr'),
        ('/api/packages', 'packages'),
        ('/api/twgcb/results', 'twgcb'),
        ('/api/admin/scheduler', 'scheduler'),
        ('/api/admin/jobs/status', 'jobs status'),
        ('/api/admin/alerts', 'alerts'),
        ('/api/admin/worklog', 'worklog'),
        ('/api/nmon/schedule', 'nmon schedule'),
        ('/api/admin/reports/monthly?month=2026-05', 'monthly report'),
        ('/api/admin/backups', 'backups'),
        ('/api/admin/logs/inspection', 'inspection log'),
        ('/api/admin/logs/flask?tail=10', 'flask log'),
    ]
    for path, label in apis:
        try:
            t0 = time.time()
            r = client.get(path)
            ms = (time.time()-t0)*1000
            try:
                j = json.loads(r.get_data(as_text=True))
                if isinstance(j, dict) and j.get('success') is False:
                    test(label, False, 'success=false: ' + str(j.get('error','?'))[:50])
                    continue
                json_ok = True
            except:
                json_ok = False
            slow = ms > 1000
            if not json_ok:
                test(label, False, 'JSON parse fail HTTP ' + str(r.status_code))
            elif slow:
                test(label, True, str(int(ms)) + 'ms (SLOW)', warn=True)
            else:
                test(label, True, 'HTTP ' + str(r.status_code) + ' ' + str(int(ms)) + 'ms')
        except Exception as e:
            test(label, False, 'EXCEPTION: ' + str(e)[:60])

    section('3. JS/Python 語法')
    import subprocess
    js_files = [
        '/seclog/AI/inspection/webapp/static/js/admin.js',
        '/seclog/AI/inspection/webapp/static/js/dashboard.js',
        '/seclog/AI/inspection/webapp/static/js/icons.js',
    ]
    for js in js_files:
        if not os.path.exists(js):
            test('JS exist ' + os.path.basename(js), False, 'missing')
            continue
        try:
            r = subprocess.run(['node', '--check', js], capture_output=True, text=True, timeout=10)
            ok = r.returncode == 0
            test('JS syntax ' + os.path.basename(js), ok, r.stderr[:120] if not ok else 'OK')
        except FileNotFoundError:
            test('JS syntax ' + os.path.basename(js), False, 'node not installed', warn=True)
        except Exception as e:
            test('JS syntax ' + os.path.basename(js), False, str(e)[:60])

    py_files = [
        '/seclog/AI/inspection/webapp/app.py',
        '/seclog/AI/inspection/webapp/routes/api_admin.py',
        '/seclog/AI/inspection/webapp/routes/api_hosts.py',
        '/seclog/AI/inspection/webapp/routes/api_inspections.py',
        '/seclog/AI/inspection/webapp/routes/api_twgcb.py',
        '/seclog/AI/inspection/webapp/routes/api_packages.py',
        '/seclog/AI/inspection/webapp/routes/api_nmon.py',
        '/seclog/AI/inspection/scripts/probe_os.py',
        '/seclog/AI/inspection/scripts/generate_inventory.py',
    ]
    for py in py_files:
        if not os.path.exists(py):
            test('PY exist ' + os.path.basename(py), False, 'missing')
            continue
        try:
            import py_compile
            py_compile.compile(py, doraise=True)
            test('PY syntax ' + os.path.basename(py), True)
        except Exception as e:
            test('PY syntax ' + os.path.basename(py), False, str(e)[:80])

    section('4. MongoDB collections')
    try:
        from services.mongo_service import get_collection
        for col in ['hosts', 'inspections', 'users', 'twgcb_results', 'nmon_daily', 'account_audit', 'host_packages']:
            try:
                c = get_collection(col).count_documents({}, limit=1)
                test('mongo ' + col, True, 'has docs=' + str(c>0))
            except Exception as e:
                test('mongo ' + col, False, str(e)[:60])
    except Exception as e:
        test('mongo connection', False, str(e)[:80])

    section('5. 重要路徑/檔案')
    paths = [
        ('/seclog/AI/inspection/webapp', 'webapp dir'),
        ('/seclog/AI/inspection/data/version.json', 'version.json'),
        ('/seclog/AI/inspection/data/hosts_config.json', 'hosts_config.json'),
        ('/seclog/AI/inspection/data/backups', 'backups dir'),
        ('/seclog/AI/inspection/ansible/inventory/hosts.yml', 'ansible inventory'),
        ('/seclog/AI/inspection/ansible/playbooks/site.yml', 'site.yml'),
        ('/home/sysinfra/.ssh/id_ed25519', 'sysinfra SSH key'),
        ('/seclog/AI/inspection/webapp/static/favicon.ico', 'favicon'),
        ('/seclog/AI/inspection/scripts/smoke_dashboard.py', 'smoke script'),
    ]
    for p, label in paths:
        exists = os.path.exists(p)
        if exists:
            writable = os.access(p, os.W_OK) if os.path.isdir(p) else True
            test('path ' + label, True, p if writable else (p + ' (not writable)'), warn=not writable)
        else:
            test('path ' + label, False, p + ' missing')

    section('6. systemd 服務')
    for svc in ['itagent-web']:
        try:
            r = subprocess.run(['systemctl', 'is-active', svc], capture_output=True, text=True, timeout=5)
            active = r.stdout.strip() == 'active'
            test('systemd ' + svc, active, r.stdout.strip())
        except Exception as e:
            test('systemd ' + svc, False, str(e)[:60])

    section('7. 業務流程')
    try:
        from services.mongo_service import get_collection
        hosts = list(get_collection('hosts').find({}, {'hostname':1, '_id':0}))
        test('hosts count', len(hosts) > 0, str(len(hosts)) + ' hosts')
        for h in hosts[:2]:
            hn = h.get('hostname')
            insp = get_collection('inspections').find_one({'hostname': hn})
            test('inspection (' + hn + ')', insp is not None, 'has data' if insp else 'no record', warn=insp is None)
    except Exception as e:
        test('biz flow', False, str(e)[:60])

    section('8. CSS/JS asset 大小')
    static_files = [
        '/seclog/AI/inspection/webapp/static/css/cathay.css',
        '/seclog/AI/inspection/webapp/static/css/admin.css',
        '/seclog/AI/inspection/webapp/static/css/example.css',
        '/seclog/AI/inspection/webapp/static/js/admin.js',
        '/seclog/AI/inspection/webapp/static/js/dashboard.js',
        '/seclog/AI/inspection/webapp/static/js/icons.js',
    ]
    for f in static_files:
        if os.path.exists(f):
            sz = os.path.getsize(f)
            test('static ' + os.path.basename(f), True, str(sz//1024) + 'KB')
        else:
            test('static ' + os.path.basename(f), False, 'missing')

    section('TOTAL')
    print('PASS: ' + str(len(results['pass'])) + '  WARN: ' + str(len(results['warn'])) + '  FAIL: ' + str(len(results['fail'])))
    if results['fail']:
        print()
        print('FAILED:')
        for f in results['fail']:
            print('  X ' + f['label'] + ': ' + f['detail'])
    if results['warn']:
        print()
        print('WARNING:')
        for w in results['warn']:
            print('  ! ' + w['label'] + ': ' + w['detail'])
    return 0 if not results['fail'] else 1

if __name__ == '__main__':
    sys.exit(main())
