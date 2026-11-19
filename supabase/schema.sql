-- 熊貓藥局 Panda Pharmacy — Supabase 資料庫
-- 在 Supabase「SQL Editor」整段貼上執行一次即可（可重複執行）。
-- 網頁只呼叫下面的函式；資料表全部開 RLS 且不開放直接讀寫。

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ============ 資料表 ============

create table if not exists public.settings (
  id int primary key default 1 check (id = 1),
  data jsonb not null default '{}'::jsonb,
  admin_salt text,
  admin_hash text,
  setup_code text
);

create table if not exists public.products (
  id text primary key,
  name text not null,
  name_ko text not null default '',
  brand text not null default '',
  price int not null default 0,
  cats text[] not null default '{}',
  img text not null default '',
  descr text not null default '',
  keywords text not null default '',
  sort int not null default 0,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table if not exists public.members (
  account text primary key,          -- 小寫：line:xxx / 微信:xxx
  name text not null,
  pw_hash text not null,
  salt text not null,
  created_at timestamptz not null default now(),
  token text unique,
  token_exp timestamptz,
  method text not null default '',
  cid text not null default ''
);

create table if not exists public.orders (
  no text primary key,
  created_at timestamptz not null default now(),
  account text not null default '',
  name text not null default '',
  pickup text not null default '',
  pickup_date text not null default '',
  note text not null default '',
  item_count int not null default 0,
  subtotal int not null default 0,
  discount int not null default 0,
  refund int not null default 0,
  net int not null default 0,
  status text not null default '新訂單',
  items jsonb not null default '[]'::jsonb,
  coupon text not null default '',
  contact text not null default ''
);
create index if not exists orders_account_idx on public.orders (lower(account));

create table if not exists public.admin_sessions (
  token text primary key,
  exp timestamptz not null
);

create table if not exists public.order_seq (
  day text primary key,
  seq int not null default 0
);

alter table public.settings enable row level security;
alter table public.products enable row level security;
alter table public.members enable row level security;
alter table public.orders enable row level security;
alter table public.admin_sessions enable row level security;
alter table public.order_seq enable row level security;

insert into public.settings (id, data) values (1, '{
  "shopName": "熊貓藥局 Panda Pharmacy｜臺灣客人專屬訂購網頁",
  "pickups": [{"name": "明洞", "addr": ""}, {"name": "聖水", "addr": ""}],
  "coupons": [{"code": "coolbau", "rate": 0.05}],
  "specialCategories": ["熱門活動商品", "熊貓明星賞品", "台灣人的最愛"],
  "functionCategories": ["抗痘", "保濕", "修護", "美白淡斑", "防曬", "腸胃保健", "止痛退燒", "感冒喉嚨", "眼睛保養", "營養補充", "抗老化"],
  "refundTable": [[30000,1500],[50000,3500],[75000,5000],[100000,6500],[125000,8000],[150000,9500],[175000,11000],[200000,12500],[225000,14000],[250000,16000],[275000,17000],[300000,19000],[325000,21000],[350000,23000],[375000,25000]],
  "refundAboveFrom": 400000,
  "refundAbovePct": 0.062,
  "notice": "退稅金額為依級距預估，實際以藥局開立的退稅單為準。"
}'::jsonb) on conflict (id) do nothing;

-- ============ 共用 ============

create or replace function public._ok(d jsonb) returns jsonb language sql immutable as $$ select jsonb_build_object('ok', true, 'data', d) $$;
create or replace function public._fail(m text) returns jsonb language sql immutable as $$ select jsonb_build_object('ok', false, 'error', m) $$;

create or replace function public._hash(txt text, salt text) returns text language sql immutable
as $$ select encode(extensions.digest(convert_to(salt || '|' || txt, 'UTF8'), 'sha256'), 'hex') $$;

create or replace function public._settings() returns jsonb language sql stable
as $$ select data from public.settings where id = 1 $$;

create or replace function public._product_json(p public.products) returns jsonb language sql immutable as $$
  select jsonb_build_object('id', p.id, 'name', p.name, 'nameKo', p.name_ko, 'brand', p.brand, 'price', p.price,
    'cats', to_jsonb(p.cats), 'img', p.img, 'desc', p.descr, 'keywords', p.keywords, 'sort', p.sort, 'active', p.active)
$$;

create or replace function public._order_json(o public.orders) returns jsonb language sql stable as $$
  select jsonb_build_object('no', o.no,
    'created', to_char(o.created_at at time zone 'Asia/Taipei', 'YYYY/MM/DD HH24:MI'),
    'createdDay', to_char(o.created_at at time zone 'Asia/Taipei', 'YYYY-MM-DD'),
    'account', o.account, 'contact', o.contact, 'name', o.name, 'pickup', o.pickup, 'date', o.pickup_date,
    'note', o.note, 'items', o.items, 'coupon', o.coupon, 'subtotal', o.subtotal, 'discount', o.discount,
    'refund', o.refund, 'net', o.net, 'status', o.status)
$$;

create or replace function public._refund(total int, s jsonb) returns int language plpgsql immutable as $$
declare r int := 0; row jsonb;
begin
  if total >= coalesce((s->>'refundAboveFrom')::numeric, 400000) then
    return (floor(total * coalesce((s->>'refundAbovePct')::numeric, 0) / 100) * 100)::int;
  end if;
  for row in select * from jsonb_array_elements(coalesce(s->'refundTable', '[]'::jsonb)) loop
    if total >= (row->>0)::int then r := (row->>1)::int; end if;
  end loop;
  return r;
end $$;

create or replace function public._coupon_rate(code text, s jsonb) returns numeric language plpgsql immutable as $$
declare c text := lower(trim(coalesce(code, ''))); x jsonb;
begin
  if c = '' then return 0; end if;
  for x in select * from jsonb_array_elements(coalesce(s->'coupons', '[]'::jsonb)) loop
    if lower(trim(x->>'code')) = c then return coalesce((x->>'rate')::numeric, 0); end if;
  end loop;
  return -1;
end $$;

create or replace function public._clean_name(n text) returns text language sql immutable
as $$ select upper(regexp_replace(trim(coalesce(n, '')), '\s+', ' ', 'g')) $$;
create or replace function public._valid_name(n text) returns boolean language sql immutable
as $$ select n ~ '^[A-Z][A-Z ,.''\-]{1,59}$' $$;
create or replace function public._clean_cid(c text) returns text language sql immutable
as $$ select regexp_replace(trim(coalesce(c, '')), '\s+', '', 'g') $$;

create or replace function public._member_by_token(t text) returns public.members language sql stable as $$
  select * from public.members where token = t and t is not null and t <> '' and token_exp > now() limit 1
$$;

create or replace function public._member_info(m public.members) returns jsonb language sql immutable
as $$ select jsonb_build_object('name', m.name, 'method', m.method, 'cid', m.cid) $$;

create or replace function public._issue_token(acc text) returns text language plpgsql as $$
declare t text := gen_random_uuid()::text;
begin
  update public.members set token = t, token_exp = now() + interval '60 days' where account = acc;
  return t;
end $$;

create or replace function public._is_admin(t text) returns boolean language sql stable as $$
  select exists(select 1 from public.admin_sessions where token = t and exp > now())
$$;

-- ============ 客人端 ============

create or replace function public.api_bootstrap(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare s jsonb := _settings();
begin
  return _ok(jsonb_build_object(
    'settings', s - 'coupons',
    'products', coalesce((select jsonb_agg(_product_json(p) order by p.sort, p.id) from products p
                          where p.active and p.name <> '' and p.price > 0), '[]'::jsonb)));
end $$;

create or replace function public.api_checkcoupon(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare code text := args->>0; r numeric := _coupon_rate(args->>0, _settings());
begin
  if r <= 0 then return _fail('優惠碼不正確'); end if;
  return _ok(jsonb_build_object('code', upper(trim(code)), 'rate', r));
end $$;

create or replace function public.api_register(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare method text := args->>0; cid text := _clean_cid(args->>1); nm text := _clean_name(args->>2);
  pw text := coalesce(args->>3, ''); acc text; salt text := gen_random_uuid()::text; m members;
begin
  if method is null or method not in ('LINE', '微信') then return _fail('請選擇聯繫方式（LINE 或微信）'); end if;
  if length(cid) < 2 or length(cid) > 40 then return _fail('請輸入正確的 ' || method || ' ID'); end if;
  if not _valid_name(nm) then return _fail('請輸入護照上的英文姓名（例：WANG XIAO MING）'); end if;
  if length(pw) < 6 then return _fail('密碼至少 6 碼'); end if;
  acc := lower(method || ':' || cid);
  if exists(select 1 from members where account = acc) then return _fail('這個 ' || method || ' ID 已經註冊過了，請直接登入'); end if;
  insert into members(account, name, pw_hash, salt, method, cid) values (acc, nm, _hash(pw, salt), salt, method, cid);
  select * into m from members where account = acc;
  return _ok(jsonb_build_object('token', _issue_token(acc)) || _member_info(m));
end $$;

create or replace function public.api_login(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare acc text := lower(coalesce(args->>0, '') || ':' || _clean_cid(args->>1)); m members;
begin
  select * into m from members where account = acc;
  if m.account is null or _hash(coalesce(args->>2, ''), m.salt) <> m.pw_hash then return _fail('ID 或密碼錯誤'); end if;
  return _ok(jsonb_build_object('token', _issue_token(acc)) || _member_info(m));
end $$;

create or replace function public.api_me(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare m members := _member_by_token(args->>0);
begin
  if m.account is null then return _fail('LOGIN'); end if;
  return _ok(_member_info(m));
end $$;

create or replace function public.api_myorders(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare m members := _member_by_token(args->>0);
begin
  if m.account is null then return _fail('LOGIN'); end if;
  return _ok(coalesce((select jsonb_agg(_order_json(o) order by o.created_at desc) from orders o
                       where lower(o.account) = lower(m.account)), '[]'::jsonb));
end $$;

create or replace function public.api_placeorder(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare m members := _member_by_token(args->>0); pl jsonb := coalesce(args->1, '{}'::jsonb); s jsonb := _settings();
  d text; today text; nm text; rate numeric; cpn text; method text; cid text; contact text;
  it jsonb; p products; qty int; items jsonb := '[]'::jsonb; sub int := 0; disc int; ref int;
  vday text; sq int; ono text; o orders;
begin
  if m.account is null then return _fail('LOGIN'); end if;
  if jsonb_array_length(coalesce(pl->'items', '[]'::jsonb)) = 0 then return _fail('購物車是空的'); end if;
  if not exists(select 1 from jsonb_array_elements(s->'pickups') x where x->>'name' = pl->>'pickup') then
    return _fail('請選擇取貨地點'); end if;
  d := coalesce(pl->>'date', '');
  today := to_char(now() at time zone 'Asia/Seoul', 'YYYY-MM-DD');
  if d !~ '^\d{4}-\d{2}-\d{2}$' then return _fail('請選擇預計取貨日'); end if;
  if d < today then return _fail('預計取貨日不能早於今天'); end if;
  nm := _clean_name(coalesce(nullif(pl->>'name', ''), m.name));
  if not _valid_name(nm) then return _fail('請輸入護照上的英文姓名（例：WANG XIAO MING）'); end if;
  rate := _coupon_rate(pl->>'coupon', s);
  if rate < 0 then return _fail('優惠碼不正確，請重新輸入或清空'); end if;
  cpn := case when rate > 0 then upper(trim(pl->>'coupon')) else '' end;
  method := coalesce(nullif(pl->>'method', ''), m.method);
  cid := _clean_cid(coalesce(nullif(pl->>'cid', ''), m.cid));
  if method is null or method not in ('LINE', '微信') then return _fail('請選擇聯繫方式（LINE 或微信）'); end if;
  if length(cid) < 2 or length(cid) > 40 then return _fail('請輸入 ' || method || ' ID'); end if;
  contact := method || '：' || cid;

  -- 價格一律以資料庫為準
  for it in select * from jsonb_array_elements(pl->'items') loop
    select * into p from products where id = it->>'id';
    if p.id is null or not p.active or p.name = '' then continue; end if;
    qty := greatest(1, least(99, coalesce((it->>'qty')::int, 1)));
    items := items || jsonb_build_object('id', p.id, 'name', p.name, 'nameKo', p.name_ko, 'brand', p.brand,
                                         'price', p.price, 'qty', qty, 'amount', p.price * qty);
    sub := sub + p.price * qty;
  end loop;
  if jsonb_array_length(items) = 0 then return _fail('商品已下架，請重新整理'); end if;
  disc := round(sub * greatest(rate, 0));
  ref := _refund(sub, s);

  vday := to_char(now() at time zone 'Asia/Taipei', 'YYMMDD');
  insert into order_seq as q (day, seq) values (vday, 1)
    on conflict on constraint order_seq_pkey do update set seq = q.seq + 1 returning q.seq into sq;
  ono := 'CB' || vday || lpad(sq::text, 3, '0');
  insert into orders(no, account, name, pickup, pickup_date, note, item_count, subtotal, discount, refund, net, status, items, coupon, contact)
    values (ono, m.account, nm, pl->>'pickup', d, left(coalesce(pl->>'note', ''), 300), jsonb_array_length(items),
            sub, disc, ref, sub - disc - ref, '新訂單', items, cpn, contact)
    returning * into o;
  return _ok(_order_json(o));
end $$;

-- ============ 後台 ============

create or replace function public.admin_login(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare st settings; t text := gen_random_uuid()::text;
begin
  select * into st from settings where id = 1;
  if st.admin_hash is null then return _fail('NEED_SETUP'); end if;
  if _hash(coalesce(args->>0, ''), st.admin_salt) <> st.admin_hash then
    perform pg_sleep(1); return _fail('密碼錯誤'); end if;
  delete from admin_sessions where exp < now();
  insert into admin_sessions(token, exp) values (t, now() + interval '12 hours');
  return _ok(jsonb_build_object('token', t));
end $$;

-- 第一次設定管理密碼（需要設定碼）；之後可用舊密碼改新密碼
create or replace function public.admin_setpassword(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare st settings; proof text := coalesce(args->>0, ''); pw text := coalesce(args->>1, ''); salt text := gen_random_uuid()::text;
begin
  select * into st from settings where id = 1;
  if length(pw) < 8 then return _fail('新密碼至少 8 碼'); end if;
  if st.admin_hash is null then
    if st.setup_code is null or proof <> st.setup_code then perform pg_sleep(1); return _fail('設定碼不正確'); end if;
  elsif _hash(proof, st.admin_salt) <> st.admin_hash then
    perform pg_sleep(1); return _fail('舊密碼不正確');
  end if;
  update settings set admin_salt = salt, admin_hash = _hash(pw, salt), setup_code = null where id = 1;
  delete from admin_sessions;
  return _ok('true'::jsonb);
end $$;

create or replace function public.admin_bootstrap(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not _is_admin(args->>0) then return _fail('LOGIN'); end if;
  return _ok(jsonb_build_object(
    'settings', _settings(),
    'products', coalesce((select jsonb_agg(_product_json(p) order by p.sort, p.id) from products p), '[]'::jsonb),
    'orders', coalesce((select jsonb_agg(_order_json(o) order by o.created_at desc) from orders o), '[]'::jsonb),
    'statuses', '["新訂單","已傳藥局","已留貨","已取貨","已取消"]'::jsonb));
end $$;

create or replace function public.admin_saveproduct(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare p jsonb := coalesce(args->1, '{}'::jsonb); pid text; r products; cats text[];
begin
  if not _is_admin(args->>0) then return _fail('LOGIN'); end if;
  if trim(coalesce(p->>'name', '')) = '' then return _fail('請輸入商品名稱'); end if;
  pid := coalesce(nullif(p->>'id', ''), 'P' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 9)));
  select coalesce(array_agg(x), '{}') into cats from jsonb_array_elements_text(coalesce(p->'cats', '[]'::jsonb)) x;
  insert into products(id, name, name_ko, brand, price, cats, img, descr, keywords, sort, active, updated_at)
    values (pid, trim(p->>'name'), coalesce(p->>'nameKo', ''), coalesce(p->>'brand', ''), coalesce((p->>'price')::numeric, 0)::int,
            cats, coalesce(p->>'img', ''), coalesce(p->>'desc', ''), coalesce(p->>'keywords', ''),
            coalesce((p->>'sort')::numeric, 0)::int, coalesce((p->>'active')::boolean, true), now())
    on conflict (id) do update set name = excluded.name, name_ko = excluded.name_ko, brand = excluded.brand,
      price = excluded.price, cats = excluded.cats, img = excluded.img, descr = excluded.descr,
      keywords = excluded.keywords, sort = excluded.sort, active = excluded.active, updated_at = now()
    returning * into r;
  return _ok(_product_json(r));
end $$;

create or replace function public.admin_deleteproduct(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not _is_admin(args->>0) then return _fail('LOGIN'); end if;
  delete from products where id = args->>1;
  return _ok('true'::jsonb);
end $$;

create or replace function public.admin_setstatus(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not _is_admin(args->>0) then return _fail('LOGIN'); end if;
  if coalesce(args->>2, '') not in ('新訂單','已傳藥局','已留貨','已取貨','已取消') then return _fail('狀態不正確'); end if;
  update orders set status = args->>2 where no = args->>1;
  if not found then return _fail('找不到訂單'); end if;
  return _ok('true'::jsonb);
end $$;

create or replace function public.admin_savesettings(args jsonb default '[]') returns jsonb
language plpgsql security definer set search_path = public as $$
declare s jsonb := _settings() || coalesce(args->1, '{}'::jsonb);
begin
  if not _is_admin(args->>0) then return _fail('LOGIN'); end if;
  s := s - 'discountRate';
  s := jsonb_set(s, '{coupons}', coalesce((select jsonb_agg(jsonb_build_object('code', trim(c->>'code'),
          'rate', least(0.5, greatest(0, coalesce((c->>'rate')::numeric, 0)))))
        from jsonb_array_elements(coalesce(s->'coupons', '[]'::jsonb)) c
        where trim(coalesce(c->>'code', '')) <> '' and coalesce((c->>'rate')::numeric, 0) > 0), '[]'::jsonb));
  s := jsonb_set(s, '{refundAbovePct}', to_jsonb(least(0.1, greatest(0, coalesce((s->>'refundAbovePct')::numeric, 0)))));
  s := jsonb_set(s, '{refundAboveFrom}', to_jsonb(coalesce(nullif((s->>'refundAboveFrom')::numeric, 0), 400000)));
  s := jsonb_set(s, '{refundTable}', coalesce((select jsonb_agg(jsonb_build_array((r->>0)::numeric::int, (r->>1)::numeric::int) order by (r->>0)::numeric)
        from jsonb_array_elements(coalesce(s->'refundTable', '[]'::jsonb)) r where (r->>0)::numeric > 0), '[]'::jsonb));
  update settings set data = s where id = 1;
  return _ok(s);
end $$;

-- 只讓網頁（anon）呼叫 api_ / admin_ 開頭的函式
revoke all on all functions in schema public from public, anon, authenticated;
grant execute on function public.api_bootstrap(jsonb), public.api_checkcoupon(jsonb), public.api_register(jsonb),
  public.api_login(jsonb), public.api_me(jsonb), public.api_myorders(jsonb), public.api_placeorder(jsonb),
  public.admin_login(jsonb), public.admin_setpassword(jsonb), public.admin_bootstrap(jsonb),
  public.admin_saveproduct(jsonb), public.admin_deleteproduct(jsonb), public.admin_setstatus(jsonb),
  public.admin_savesettings(jsonb)
  to anon, authenticated;
