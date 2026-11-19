#!/usr/bin/env python3
"""把 Google 試算表（匯出的 .xlsx）轉成 Supabase 用的 migrate.sql。
用法：python3 migrate.py <試算表.xlsx> <輸出.sql> <設定碼>"""
import datetime as dt, json, re, sys
from openpyxl import load_workbook

src, out, setup_code = sys.argv[1], sys.argv[2], sys.argv[3]
wb = load_workbook(src, data_only=True)
TPE = dt.timezone(dt.timedelta(hours=8))

def q(v):
    if v is None: return "''"
    return "'" + str(v).replace("'", "''") + "'"
def rows(name):
    ws = wb[name]; it = ws.iter_rows(values_only=True); head = [str(h or '') for h in next(it)]
    return [dict(zip(head, r)) for r in it if any(c not in (None, '') for c in r)]
def ts(v):
    if isinstance(v, dt.datetime): return q(v.replace(tzinfo=TPE).isoformat())
    if isinstance(v, dt.date): return q(dt.datetime(v.year, v.month, v.day, tzinfo=TPE).isoformat())
    return 'now()'
def ymd(v):
    if isinstance(v, (dt.datetime, dt.date)): return v.strftime('%Y-%m-%d')
    m = re.match(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})', str(v or ''))
    return f'{m[1]}-{int(m[2]):02d}-{int(m[3]):02d}' if m else str(v or '')
def num(v):
    try: return int(round(float(v)))
    except Exception: return 0
def truthy(v):
    return v is True or str(v).strip().upper() not in ('FALSE', '否', 'N', 'NO', '0', '下架')

sql = ['begin;', 'delete from public.products;', 'delete from public.orders;', 'delete from public.members;', 'delete from public.order_seq;']

for i, r in enumerate(rows('商品')):
    if not str(r.get('名稱') or '').strip(): continue
    cats = [c.strip() for c in re.split('[、,，]', str(r.get('類別') or '')) if c.strip()]
    sql.append('insert into public.products(id,name,name_ko,brand,price,cats,img,descr,keywords,sort,active) values (%s,%s,%s,%s,%d,%s,%s,%s,%s,%d,%s);' % (
        q(r.get('id') or f'R{i + 2}'), q(r['名稱']), q(r.get('韓文名稱')), q(r.get('品牌')), num(r.get('價格KRW')),
        q('{' + ','.join('"' + c.replace('"', '') + '"' for c in cats) + '}') + '::text[]',
        q(r.get('圖片網址')), q(r.get('說明')), q(r.get('搜尋關鍵字')), num(r.get('排序')) or (i + 1) * 10,
        'true' if truthy(r.get('上架')) else 'false'))

for r in rows('會員'):
    if not r.get('帳號'): continue
    sql.append('insert into public.members(account,name,pw_hash,salt,created_at,token,token_exp,method,cid) values (%s,%s,%s,%s,%s,%s,%s,%s,%s) on conflict do nothing;' % (
        q(str(r['帳號']).lower()), q(r.get('護照英文姓名')), q(r.get('密碼雜湊')), q(r.get('鹽')), ts(r.get('建立時間')),
        'null' if not r.get('token') else q(r['token']), 'null' if not r.get('token到期') else ts(r['token到期']),
        q(r.get('聯繫方式')), q(r.get('聯繫ID'))))

seq = {}
for r in rows('訂單'):
    no = str(r.get('訂單編號') or '')
    if not no: continue
    m = re.match(r'CB(\d{6})(\d+)', no)
    if m: seq[m[1]] = max(seq.get(m[1], 0), int(m[2]))
    items = r.get('明細JSON') or '[]'
    json.loads(items)
    sql.append('insert into public.orders(no,created_at,account,name,pickup,pickup_date,note,item_count,subtotal,discount,refund,net,status,items,coupon,contact) values (%s,%s,%s,%s,%s,%s,%s,%d,%d,%d,%d,%d,%s,%s::jsonb,%s,%s);' % (
        q(no), ts(r.get('建立時間')), q(str(r.get('會員帳號') or '').lower()), q(r.get('護照英文姓名')), q(r.get('取貨地點')),
        q(ymd(r.get('預計取貨日'))), q(r.get('備註')), num(r.get('品項數')), num(r.get('總價')), num(r.get('優惠折扣')),
        num(r.get('預估退稅')), num(r.get('預估實付')), q(r.get('狀態') or '新訂單'), q(items), q(r.get('優惠碼')), q(r.get('聯繫方式'))))
for d, n in seq.items():
    sql.append(f"insert into public.order_seq(day, seq) values ('{d}', {n});")

st = rows('設定')
data = None
ws = wb['設定']
v = ws.cell(row=2, column=1).value
if v:
    data = json.loads(v)
    data.pop('discountRate', None)
    if re.search('pham', data.get('shopName', ''), re.I):
        data['shopName'] = '熊貓藥局 Panda Pharmacy｜臺灣客人專屬訂購網頁'
    sql.append('update public.settings set data = %s::jsonb where id = 1;' % q(json.dumps(data, ensure_ascii=False)))
sql.append('update public.settings set setup_code = %s, admin_hash = null, admin_salt = null where id = 1;' % q(setup_code))
sql.append('commit;')
open(out, 'w', encoding='utf8').write('\n'.join(sql) + '\n')
print('products', sum(1 for s in sql if 'into public.products' in s), 'members', sum(1 for s in sql if 'into public.members' in s),
      'orders', sum(1 for s in sql if 'into public.orders' in s), 'settings', bool(data))
