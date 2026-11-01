-- מנהלים והרשאות: admin = ניהול מלא, viewer = צפייה ודוחות בלבד

alter table admins add column if not exists name text;
alter table admins add column if not exists role text not null default 'admin' check (role in ('admin', 'viewer'));
alter table admins add column if not exists active boolean not null default true;
alter table admins add column if not exists created_at timestamptz not null default now();

create or replace function is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where user_id = auth.uid() and active and role = 'admin');
$$;

create or replace function is_staff() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins where user_id = auth.uid() and active);
$$;

-- צפייה לכל מנהל פעיל, כתיבה רק למנהל מלא
create policy staff_read on drivers     for select to authenticated using (is_staff());
create policy staff_read on trucks      for select to authenticated using (is_staff());
create policy staff_read on punches     for select to authenticated using (is_staff());
create policy staff_read on punch_voids for select to authenticated using (is_staff());

create or replace function audit_log()
returns table (at timestamptz, action text, punch_id bigint, driver_id int, kind text, punch_at timestamptz, reason text, by_email text)
language sql stable security definer set search_path = public as $$
  select v.voided_at, 'ביטול', v.punch_id, p.driver_id, p.kind, p.at, v.reason, u.email::text
    from punch_voids v join punches p on p.id = v.punch_id left join auth.users u on u.id = v.voided_by
   where is_staff()
  union all
  select p.created_at, 'רשומה ידנית', p.id, p.driver_id, p.kind, p.at, p.reason, u.email::text
    from punches p left join auth.users u on u.id = p.created_by
   where p.manual and is_staff()
  order by 1 desc
$$;

create or replace function my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from admins where user_id = auth.uid() and active;
$$;

create or replace function list_managers()
returns table (user_id uuid, email text, name text, role text, active boolean, created_at timestamptz, last_sign_in_at timestamptz)
language sql stable security definer set search_path = public as $$
  select a.user_id, u.email::text, a.name, a.role, a.active, a.created_at, u.last_sign_in_at
    from admins a join auth.users u on u.id = a.user_id
   where is_admin()
   order by a.created_at;
$$;

create or replace function create_manager(p_email text, p_password text, p_name text, p_role text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare uid uuid; em text := lower(trim(p_email));
begin
  if not is_admin() then raise exception 'אין הרשאה'; end if;
  if p_role not in ('admin', 'viewer') then raise exception 'תפקיד לא תקין'; end if;
  if em !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'אימייל לא תקין'; end if;

  select id into uid from auth.users where email = em;
  if uid is null then
    if length(coalesce(p_password, '')) < 8 then raise exception 'הסיסמה צריכה לפחות 8 תווים'; end if;
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change_token_new, email_change,
                            email_change_token_current, phone_change, phone_change_token, reauthentication_token)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
            crypt(p_password, gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', jsonb_build_object('name', p_name), now(), now(), '', '', '', '', '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text, jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true),
            'email', now(), now(), now());
  end if;

  insert into admins (user_id, name, role, active) values (uid, nullif(trim(p_name), ''), p_role, true)
  on conflict (user_id) do update set name = excluded.name, role = excluded.role, active = true;
  return uid;
end $$;

create or replace function update_manager(p_user_id uuid, p_role text, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'אין הרשאה'; end if;
  if p_user_id = auth.uid() and (p_role <> 'admin' or not p_active) then
    raise exception 'אי אפשר להוריד הרשאות לעצמך';
  end if;
  update admins set role = p_role, active = p_active where user_id = p_user_id;
end $$;

create or replace function set_manager_password(p_user_id uuid, p_password text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_admin() then raise exception 'אין הרשאה'; end if;
  if length(coalesce(p_password, '')) < 8 then raise exception 'הסיסמה צריכה לפחות 8 תווים'; end if;
  if not exists (select 1 from admins where user_id = p_user_id) then raise exception 'לא מנהל במערכת'; end if;
  update auth.users set encrypted_password = crypt(p_password, gen_salt('bf')), updated_at = now() where id = p_user_id;
end $$;

revoke all on function list_managers(), my_role(), create_manager(text, text, text, text),
  update_manager(uuid, text, boolean), set_manager_password(uuid, text) from public, anon;
grant execute on function list_managers(), my_role(), create_manager(text, text, text, text),
  update_manager(uuid, text, boolean), set_manager_password(uuid, text) to authenticated;
