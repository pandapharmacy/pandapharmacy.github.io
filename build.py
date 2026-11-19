#!/usr/bin/env python3
"""建置：把 src/Shared.html 併入頁面，填入 Supabase 設定，輸出到 docs/（GitHub Pages）。
用法：python3 build.py <SUPABASE_URL> <ANON_KEY> [輸出資料夾]"""
import os, re, subprocess, sys

ROOT = os.path.dirname(os.path.abspath(__file__))
url, key = sys.argv[1].rstrip('/'), sys.argv[2]
out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(ROOT, 'docs')
os.makedirs(out, exist_ok=True)
shared = open(os.path.join(ROOT, 'src', 'Shared.html'), encoding='utf8').read()
for src, dst in (('Store.html', 'index.html'), ('Admin.html', 'admin.html')):
    s = open(os.path.join(ROOT, 'src', src), encoding='utf8').read()
    s = s.replace("<?!= include('Shared'); ?>", shared).replace('%%SUPA_URL%%', url).replace('%%SUPA_KEY%%', key)
    assert '<?' not in s and '%%' not in s, src
    for i, js in enumerate(re.findall(r'<script>(.*?)</script>', s, re.S)):
        tmp = os.path.join(out, '.check.js')
        open(tmp, 'w', encoding='utf8').write(js)
        r = subprocess.run(['node', '--check', tmp], capture_output=True, text=True)
        os.remove(tmp)
        assert r.returncode == 0, f'{src} script {i}: {r.stderr}'
    open(os.path.join(out, dst), 'w', encoding='utf8').write(s)
    print('built', dst, len(s.encode('utf8')), 'bytes')
open(os.path.join(out, '.nojekyll'), 'w').close()
