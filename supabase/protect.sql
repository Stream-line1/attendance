-- הגנה ממחיקה: אי אפשר למחוק החתמות, נהגים או משאיות (נהג שעזב = השבתה)
create or replace function block_delete() returns trigger language plpgsql as $$
begin
  raise exception 'מחיקה חסומה במערכת הנוכחות';
end $$;

create trigger no_delete before delete on punches for each row execute function block_delete();
create trigger no_delete before delete on drivers for each row execute function block_delete();
create trigger no_delete before delete on trucks  for each row execute function block_delete();
create trigger no_truncate before truncate on punches for each statement execute function block_delete();
create trigger no_truncate before truncate on drivers for each statement execute function block_delete();

revoke delete, truncate on punches, drivers, trucks from anon, authenticated;

-- החתמה שנרשמה לא ניתנת לעריכה מהאתר
revoke update on punches from anon, authenticated;

select tgname, tgrelid::regclass from pg_trigger where tgname in ('no_delete', 'no_truncate');
