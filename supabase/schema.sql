-- מערכת נוכחות נהגים - הרץ את כל הקובץ ב-Supabase > SQL Editor

create extension if not exists pgcrypto;

create table drivers (
  id serial primary key,
  name text not null,
  id_number text not null unique,  -- ת.ז, 9 ספרות
  pin text not null,               -- קוד אישי לרישום טלפון בפעם הראשונה
  device_token uuid,               -- הטלפון הרשום של הנהג
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table trucks (
  id int primary key,              -- המספר שכתוב בתג
  name text not null               -- למשל מספר רישוי
);

create table punches (
  id bigserial primary key,
  driver_id int not null references drivers(id),
  truck_id int references trucks(id),
  kind text not null check (kind in ('in','out')),
  at timestamptz not null default now(),
  lat double precision,
  lng double precision,
  manual boolean not null default false
);
create index on punches (driver_id, at desc);
create index on punches (at desc);

create table admins (
  user_id uuid primary key references auth.users(id)
);

-- אבטחה: לנהגים (anon) אין גישה לטבלאות, רק לפונקציות למטה
alter table drivers enable row level security;
alter table trucks  enable row level security;
alter table punches enable row level security;
alter table admins  enable row level security;

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where user_id = auth.uid());
$$;

create policy admin_all on drivers for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_all on trucks  for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_all on punches for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_self on admins for select to authenticated using (user_id = auth.uid());

-- רישום טלפון של נהג (פעם אחת), לפי ת.ז וקוד אישי
create or replace function register_device(p_id text, p_pin text)
returns json language plpgsql security definer set search_path = public as $$
declare d drivers;
begin
  select * into d from drivers
   where id_number = lpad(regexp_replace(p_id, '\D', '', 'g'), 9, '0') and pin = p_pin and active;
  if not found then
    raise exception 'תעודת זהות או קוד שגויים';
  end if;
  update drivers set device_token = gen_random_uuid() where id = d.id returning * into d;
  return json_build_object('token', d.device_token, 'name', d.name);
end $$;

-- החתמה: כניסה/יציאה לפי הסריקה הקודמת
create or replace function punch(p_token uuid, p_truck int, p_lat double precision, p_lng double precision)
returns json language plpgsql security definer set search_path = public as $$
declare d drivers; last punches; new_kind text; p punches;
begin
  select * into d from drivers where device_token = p_token and active;
  if not found then
    raise exception 'הטלפון לא רשום';
  end if;

  select * into last from punches where driver_id = d.id order by at desc limit 1;

  -- סריקה כפולה בטעות (פחות מדקה) - מחזירים את הקודמת
  if found and last.at > now() - interval '1 minute' then
    return json_build_object('name', d.name, 'kind', last.kind, 'at', last.at, 'duplicate', true);
  end if;

  -- יציאה רק אם הייתה כניסה פתוחה ב-16 השעות האחרונות
  if found and last.kind = 'in' and last.at > now() - interval '16 hours' then
    new_kind := 'out';
  else
    new_kind := 'in';
  end if;

  insert into punches (driver_id, truck_id, kind, lat, lng)
  values (d.id, (select id from trucks where id = p_truck), new_kind, p_lat, p_lng)
  returning * into p;

  return json_build_object('name', d.name, 'kind', p.kind, 'at', p.at, 'duplicate', false);
end $$;

revoke all on function register_device(text, text) from public;
revoke all on function punch(uuid, int, double precision, double precision) from public;
grant execute on function register_device(text, text) to anon, authenticated;
grant execute on function punch(uuid, int, double precision, double precision) to anon, authenticated;

-- 70 משאיות ראשוניות (אפשר לשנות שמות במסך המנהל)
insert into trucks (id, name) select g, 'משאית ' || g from generate_series(1, 70) g;
