-- תיקוני נוכחות: הרשומה המקורית לא משתנה. תיקון = ביטול עם סיבה, או רשומה ידנית חדשה עם סיבה.

alter table punches add column if not exists reason text;
alter table punches add column if not exists created_by uuid;
alter table punches add column if not exists created_at timestamptz not null default now();
alter table punches add constraint manual_needs_reason check (not manual or coalesce(trim(reason), '') <> '');

create table punch_voids (
  punch_id bigint primary key references punches(id),
  reason text not null check (trim(reason) <> ''),
  voided_by uuid not null default auth.uid(),
  voided_at timestamptz not null default now()
);
alter table punch_voids enable row level security;
create policy admin_read on punch_voids for select to authenticated using (is_admin());
create policy admin_insert on punch_voids for insert to authenticated with check (is_admin());
revoke update, delete, truncate on punch_voids from anon, authenticated;
create trigger no_delete before delete on punch_voids for each row execute function block_delete();

-- ברשומה ידנית נרשם תמיד מי יצר אותה
create or replace function enforce_manual() returns trigger language plpgsql as $$
begin
  if new.manual then
    new.created_by := auth.uid();
  end if;
  return new;
end $$;
create trigger enforce_manual before insert on punches for each row execute function enforce_manual();

-- יומן ביקורת: מי עשה מה ומתי (למנהלים בלבד)
create or replace function audit_log()
returns table (at timestamptz, action text, punch_id bigint, driver_id int, kind text, punch_at timestamptz, reason text, by_email text)
language sql stable security definer set search_path = public as $$
  select v.voided_at, 'ביטול', v.punch_id, p.driver_id, p.kind, p.at, v.reason, u.email::text
    from punch_voids v join punches p on p.id = v.punch_id left join auth.users u on u.id = v.voided_by
   where is_admin()
  union all
  select p.created_at, 'רשומה ידנית', p.id, p.driver_id, p.kind, p.at, p.reason, u.email::text
    from punches p left join auth.users u on u.id = p.created_by
   where p.manual and is_admin()
  order by 1 desc
$$;
revoke all on function audit_log() from public, anon;
grant execute on function audit_log() to authenticated;

-- החתמה: רשומה מבוטלת לא נחשבת כשקובעים כניסה או יציאה
create or replace function punch(p_token uuid, p_truck int, p_lat double precision, p_lng double precision)
returns json language plpgsql security definer set search_path = public as $$
declare d drivers; last punches; new_kind text; p punches;
begin
  select * into d from drivers where device_token = p_token and active;
  if not found then
    raise exception 'הטלפון לא רשום';
  end if;

  select * into last from punches
   where driver_id = d.id and id not in (select punch_id from punch_voids)
   order by at desc limit 1;

  if found and last.at > now() - interval '1 minute' then
    return json_build_object('name', d.name, 'kind', last.kind, 'at', last.at, 'duplicate', true);
  end if;

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
