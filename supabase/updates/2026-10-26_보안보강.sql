-- 궁궐 사람들 키트 변경 2026-10-26: 보안 보강(이미 설치한 학교용. 새로 설치하는 학교는 install.sql만 실행하면 된다)
-- 1) 교사 로그인 12시간 뒤 끊김  2) 학생 비밀번호 5번 틀리면 15분 잠금(저절로 풀림)
-- 3) 설치 코드 12자리·24시간 유효·전체 시도 제한  4) 관리자가 정해 준 교사 비밀번호는 첫 로그인 때 바꾸기
-- SQL Editor에 통째로 붙여 넣고 Run. 여러 번 실행해도 된다.

alter table public.gp_settings add column if not exists setup_until timestamptz default now() + interval '24 hours';
alter table public.gp_staff add column if not exists must_change boolean not null default false;
alter table public.gp_students add column if not exists locked_until timestamptz;
alter table public.gp_login_fail add column if not exists kind text not null default 'login';
drop function if exists public.gp_note_fail();

create or replace function public.gp_my_staff()
returns public.gp_staff language sql stable security definer set search_path = '' as $$
  select s.* from public.gp_staff s
  where s.id = (select b.ref from public.gp_bind b where b.uid = (select auth.uid()) and b.kind = 'staff'
                  and b.created_at > now() - interval '12 hours')   -- 교사 로그인은 12시간 뒤 끊긴다(공용 PC 대비)
     or (s.email is not null and s.email = public.gp_google_email())
  limit 1
$$;

create or replace function public.gp_note_fail(p_kind text default 'login')
returns void language sql security definer set search_path = '' as $$
  insert into public.gp_login_fail(uid, kind) values ((select auth.uid()), p_kind);
  delete from public.gp_login_fail where at < now() - interval '1 day';
$$;

create or replace function public.gp_public()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'school_name', c.school_name, 'event_label', c.event_label, 'meet_text', c.meet_text, 'museum_time', c.museum_time,
    'rules', c.rules, 'privacy', c.privacy, 'class_count', c.class_count, 'max_num', c.max_num, 'role_cap', c.role_cap,
    'min_diary', c.min_diary, 'min_reflect', c.min_reflect,
    'role_change_until', c.role_change_until, 'mission_open_at', c.mission_open_at, 'ending_open_at', c.ending_open_at,
    'mission_close_at', c.mission_close_at, 'ending_close_at', c.ending_close_at,
    'auth_mode', c.auth_mode, 'google_domain', c.google_domain,
    'setup_needed', c.setup_code is not null and now() < c.setup_until and not exists (select 1 from public.gp_staff where kind = 'admin'),
    'setup_expired', c.setup_code is not null and now() >= c.setup_until and not exists (select 1 from public.gp_staff where kind = 'admin'),
    'now', now())
  from public.gp_settings c
$$;

create or replace function public.gp_setup(p_code text, p_login_id text, p_name text, p_pw text)
returns text language plpgsql security definer set search_path = '' as $$
declare c public.gp_settings; v_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'no_session'; end if;
  select * into c from public.gp_settings for update;
  if exists (select 1 from public.gp_staff where kind = 'admin') or c.setup_code is null then return 'already'; end if;
  if c.setup_until is null or now() > c.setup_until then return 'expired'; end if;
  -- 기기마다 10분 15번, 모든 기기를 합쳐 1시간 30번까지만 시도할 수 있다.
  if public.gp_too_many_fails() or (select count(*) from public.gp_login_fail where kind = 'setup' and at > now() - interval '1 hour') >= 30 then return 'slow_down'; end if;
  if upper(btrim(coalesce(p_code, ''))) <> c.setup_code then perform public.gp_note_fail('setup'); return 'bad_code'; end if;
  if lower(btrim(coalesce(p_login_id, ''))) !~ '^[a-z0-9_.-]{3,30}$' then return 'bad_id'; end if;
  if char_length(coalesce(p_pw, '')) < 8 then return 'short_pw'; end if;
  if char_length(btrim(coalesce(p_name, ''))) not between 1 and 20 then return 'bad_name'; end if;
  insert into public.gp_staff(login_id, pw_hash, name, kind)
  values (lower(btrim(p_login_id)), extensions.crypt(p_pw, extensions.gen_salt('bf', 8)), btrim(p_name), 'admin')
  returning id into v_id;
  update public.gp_settings set setup_code = null where id;   -- Supabase는 WHERE 없는 UPDATE·DELETE를 막는다(pg_safeupdate)
  perform public.gp_bind_me('staff', v_id);
  return 'ok';
end $$;

create or replace function public.gp_staff_login(p_login_id text, p_pw text)
returns text language plpgsql security definer set search_path = '' as $$
declare st public.gp_staff;
begin
  if (select auth.uid()) is null then raise exception 'no_session'; end if;
  if public.gp_too_many_fails() then return 'slow_down'; end if;
  select * into st from public.gp_staff where login_id = lower(btrim(coalesce(p_login_id, ''))) for update;
  if st.id is null or st.pw_hash is null then perform public.gp_note_fail(); return 'mismatch'; end if;
  if st.locked_until is not null and st.locked_until > now() then return 'locked'; end if;
  if st.pw_hash <> extensions.crypt(coalesce(p_pw, ''), st.pw_hash) then
    update public.gp_staff set fails = fails + 1,
      locked_until = case when fails + 1 >= 8 then now() + interval '15 minutes' end where id = st.id;
    perform public.gp_note_fail();
    return 'mismatch';
  end if;
  update public.gp_staff set fails = 0, locked_until = null where id = st.id;
  delete from public.gp_bind where kind = 'staff' and created_at < now() - interval '12 hours';
  perform public.gp_bind_me('staff', st.id);
  return 'ok';
end $$;

create or replace function public.gp_staff_password(p_old text, p_new text)
returns text language plpgsql security definer set search_path = '' as $$
declare st public.gp_staff;
begin
  st := public.gp_require_staff();
  if st.pw_hash is not null and st.pw_hash <> extensions.crypt(coalesce(p_old, ''), st.pw_hash) then return 'mismatch'; end if;
  if char_length(coalesce(p_new, '')) < 8 then return 'short_pw'; end if;
  if p_new = p_old then return 'same_pw'; end if;
  update public.gp_staff set pw_hash = extensions.crypt(p_new, extensions.gen_salt('bf', 8)), must_change = false where id = st.id;
  return 'ok';
end $$;

create or replace function public.gp_student_enter(p_join text, p_class smallint, p_num smallint, p_name text, p_pin text)
returns text language plpgsql security definer set search_path = '' as $$
declare c public.gp_settings; s public.gp_students; v_name text := btrim(coalesce(p_name, ''));
begin
  if (select auth.uid()) is null then raise exception 'no_session'; end if;
  c := public.gp_cfg();
  if c.auth_mode <> 'code' then return 'google_only'; end if;
  if public.gp_too_many_fails() then return 'slow_down'; end if;
  if upper(btrim(coalesce(p_join, ''))) <> c.join_code then perform public.gp_note_fail(); return 'bad_join'; end if;
  if p_class is null or p_class not between 1 and c.class_count then return 'bad_class'; end if;
  if p_num is null or p_num not between 1 and c.max_num then return 'bad_num'; end if;
  if char_length(v_name) not between 1 and 20 then return 'bad_name'; end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then return 'bad_pin'; end if;
  select * into s from public.gp_students where class_no = p_class and num = p_num for update;
  if s.id is null then
    insert into public.gp_students(class_no, num, name, pin_hash)
    values (p_class, p_num, v_name, extensions.crypt(p_pin, extensions.gen_salt('bf', 6))) returning * into s;
    perform public.gp_bind_me('student', s.id);
    return 'new';
  end if;
  if s.locked_until is not null and s.locked_until > now() then return 'locked'; end if;
  if public.gp_norm(s.name) <> public.gp_norm(v_name) or s.email is not null then
    update public.gp_students set fails = case when fails + 1 >= 5 then 0 else fails + 1 end,
      locked_until = case when fails + 1 >= 5 then now() + interval '15 minutes' else locked_until end where id = s.id;
    perform public.gp_note_fail();
    return 'mismatch';
  end if;
  if s.pin_hash is null then          -- 담임이 비밀번호를 지운 학생: 이번에 새로 정한다
    update public.gp_students set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 6)), fails = 0, updated_at = now() where id = s.id;
  elsif s.pin_hash <> extensions.crypt(p_pin, s.pin_hash) then
    update public.gp_students set fails = case when fails + 1 >= 5 then 0 else fails + 1 end,
      locked_until = case when fails + 1 >= 5 then now() + interval '15 minutes' else locked_until end where id = s.id;
    perform public.gp_note_fail();
    return 'mismatch';
  else
    update public.gp_students set fails = 0, locked_until = null where id = s.id;
  end if;
  perform public.gp_bind_me('student', s.id);
  return 'ok';
end $$;

create or replace function public.gp_me()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare st public.gp_staff; s public.gp_students;
begin
  st := public.gp_my_staff();
  select * into s from public.gp_students where id = public.gp_my_sid();
  return jsonb_build_object(
    'staff', case when st.id is null then null else jsonb_build_object('id', st.id, 'name', st.name, 'kind', st.kind,
      'classes', to_jsonb(st.classes), 'login_id', st.login_id, 'must_change', st.must_change) end,
    'student', case when s.id is null then null else jsonb_build_object('id', s.id, 'class_no', s.class_no, 'num', s.num,
      'name', s.name, 'role_id', s.role_id, 'checkin_at', s.checkin_at, 'checkout_at', s.checkout_at,
      'tester', s.staff_id is not null) end,
    'google', public.gp_google_email(),
    'now', now());
end $$;

create or replace function public.gp_class_status(p_class smallint)
returns table(sid uuid, num smallint, name text, role_id text, role_at timestamptz, checkin_at timestamptz, checkout_at timestamptz,
              missions int, final_done boolean, reflect_len int, locked boolean, has_pin boolean, google boolean)
language plpgsql stable security definer set search_path = '' as $$
declare st public.gp_staff; md int := (public.gp_cfg()).min_diary;
begin
  st := public.gp_require_staff();
  if p_class = 0 then
    return query select s.id, s.num, s.name, s.role_id, s.role_at, s.checkin_at, s.checkout_at,
      (select count(*)::int from public.gp_entries e where e.student_id = s.id and e.photo_path is not null and char_length(coalesce(e.diary, '')) >= md),
      exists (select 1 from public.gp_final f where f.student_id = s.id and f.note is not null),
      coalesce((select char_length(f.reflection) from public.gp_final f where f.student_id = s.id), 0),
      false, true, false
    from public.gp_students s where s.staff_id is not null and (st.kind = 'admin' or s.staff_id = st.id) order by s.num;
    return;
  end if;
  if not public.gp_can_view_class(p_class) then raise exception 'not_staff' using errcode = '42501'; end if;
  return query select s.id, s.num, s.name, s.role_id, s.role_at, s.checkin_at, s.checkout_at,
    (select count(*)::int from public.gp_entries e where e.student_id = s.id and e.photo_path is not null and char_length(coalesce(e.diary, '')) >= md),
    exists (select 1 from public.gp_final f where f.student_id = s.id and f.note is not null),
    coalesce((select char_length(f.reflection) from public.gp_final f where f.student_id = s.id), 0),
    s.locked_until is not null and s.locked_until > now(), s.pin_hash is not null, s.email is not null
  from public.gp_students s where s.class_no = p_class and s.staff_id is null order by s.num, s.name;
end $$;

create or replace function public.gp_reset_pin(p_sid uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.gp_can_view(p_sid) then raise exception 'not_staff' using errcode = '42501'; end if;
  update public.gp_students set pin_hash = null, fails = 0, locked_until = null, updated_at = now() where id = p_sid and staff_id is null;
  delete from public.gp_bind where kind = 'student' and ref = p_sid;
end $$;

create or replace function public.gp_admin_save_staff(p jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare me public.gp_staff; v_id uuid := nullif(p->>'id', '')::uuid; v_login text := lower(btrim(coalesce(p->>'login_id', '')));
  v_kind text := coalesce(p->>'kind', 'homeroom'); v_classes smallint[]; v_email text := nullif(lower(btrim(coalesce(p->>'email', ''))), '');
  v_pw text := p->>'password';
begin
  me := public.gp_require_admin();
  if v_login !~ '^[a-z0-9_.-]{3,30}$' then return 'bad_id'; end if;
  if char_length(btrim(coalesce(p->>'name', ''))) not between 1 and 20 then return 'bad_name'; end if;
  if v_kind not in ('admin', 'homeroom') then return 'bad_kind'; end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return 'bad_email'; end if;
  select coalesce(array_agg(x::smallint), '{}') into v_classes from jsonb_array_elements_text(coalesce(p->'classes', '[]'::jsonb)) x
    where x ~ '^[0-9]{1,2}$';
  if v_pw is not null and v_pw <> '' and char_length(v_pw) < 8 then return 'short_pw'; end if;
  if exists (select 1 from public.gp_staff where login_id = v_login and id is distinct from v_id) then return 'dup_id'; end if;
  if v_email is not null and exists (select 1 from public.gp_staff where email = v_email and id is distinct from v_id) then return 'dup_email'; end if;
  if v_id is null then
    if coalesce(v_pw, '') = '' and v_email is null then return 'short_pw'; end if;
    insert into public.gp_staff(login_id, pw_hash, email, name, kind, classes, must_change)
    values (v_login, case when coalesce(v_pw, '') <> '' then extensions.crypt(v_pw, extensions.gen_salt('bf', 8)) end,
      v_email, btrim(p->>'name'), v_kind, v_classes, coalesce(v_pw, '') <> '');
  else
    if v_id = me.id and v_kind <> 'admin' then return 'last_admin'; end if;
    update public.gp_staff set login_id = v_login, email = v_email, name = btrim(p->>'name'), kind = v_kind, classes = v_classes,
      pw_hash = case when coalesce(v_pw, '') <> '' then extensions.crypt(v_pw, extensions.gen_salt('bf', 8)) else pw_hash end,
      must_change = case when coalesce(v_pw, '') <> '' then v_id <> me.id else must_change end,
      fails = 0, locked_until = null
    where id = v_id;
    if coalesce(v_pw, '') <> '' and v_id <> me.id then delete from public.gp_bind where kind = 'staff' and ref = v_id; end if;
  end if;
  return 'ok';
end $$;

create or replace function public.gp_admin_get()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare c public.gp_settings;
begin
  perform public.gp_require_admin();
  c := public.gp_cfg();
  return jsonb_build_object(
    'settings', to_jsonb(c) - 'setup_code' - 'id',
    'staff', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'login_id', s.login_id, 'name', s.name, 'kind', s.kind,
      'classes', to_jsonb(s.classes), 'email', s.email, 'has_pw', s.pw_hash is not null,
      'locked', s.locked_until is not null and s.locked_until > now(), 'must_change', s.must_change) order by s.kind, s.login_id), '[]'::jsonb) from public.gp_staff s),
    'counts', jsonb_build_object(
      'students', (select count(*) from public.gp_students where staff_id is null),
      'entries', (select count(*) from public.gp_entries e join public.gp_students s on s.id = e.student_id where s.staff_id is null),
      'photos', (select count(*) from storage.objects where bucket_id = 'gp-photos')));
end $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('gp_my_staff', 'gp_note_fail') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
revoke all on function public.gp_public(), public.gp_setup(text, text, text, text), public.gp_staff_login(text, text),
  public.gp_staff_password(text, text), public.gp_student_enter(text, smallint, smallint, text, text), public.gp_me(),
  public.gp_class_status(smallint), public.gp_reset_pin(uuid), public.gp_admin_save_staff(jsonb), public.gp_admin_get() from public, anon, authenticated;
grant execute on function public.gp_public() to anon, authenticated;
grant execute on function public.gp_setup(text, text, text, text), public.gp_staff_login(text, text),
  public.gp_staff_password(text, text), public.gp_student_enter(text, smallint, smallint, text, text), public.gp_me(),
  public.gp_class_status(smallint), public.gp_reset_pin(uuid), public.gp_admin_save_staff(jsonb), public.gp_admin_get() to authenticated;
