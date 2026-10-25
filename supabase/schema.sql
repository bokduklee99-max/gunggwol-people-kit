-- ============================================================================
-- 궁궐 사람들 키트: 설치 SQL (표·접근 통제·함수·사진 보관함)
-- Supabase 대시보드 → SQL Editor에 install.sql을 통째로 붙여 넣고 Run 한다.
-- 모든 이름은 gp_로 시작한다. 지우기: uninstall.sql
-- 학생·교사 기록은 표를 직접 읽거나 쓸 수 없고, 아래 함수로만 다룬다.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------- 표
create table public.gp_settings (
  id boolean primary key default true check (id),
  school_name text not null default '○○고등학교',
  event_label text not null default '1학년 경복궁 현장체험학습',
  meet_text text not null default '9:20까지 경복궁 매표소 앞(3호선 경복궁역 5번 출구)',
  museum_time text not null default '10:45',
  rules jsonb not null default '[
    "정해진 시각까지 집결 장소에 모이시오. 도착하면 앱에서 출석 확인을 누르시오.",
    "궁 미션을 마치고 정해진 시각까지 국립고궁박물관 앞에 모이오. 흥례문 게이트로 나간 뒤에는 궁에 다시 들어오지 않소.",
    "박물관 미션과 엔딩을 마치면 담임 선생님께 종례를 받고 해산하오.",
    "사진은 장소와 사물만 찍으시오. 다른 사람 얼굴이 크게 나오면 안 되오.",
    "문화유산을 만지거나 올라가지 말고, 출입 금지 구역에 들어가지 마시오.",
    "휴대폰을 충전해 오시오. 사진과 글은 미션 마감 시각까지 나중에 올릴 수 있소.",
    "길을 잃거나 몸이 안 좋으면 바로 담임 선생님께 전화하시오."]'::jsonb,
  privacy text not null default '수집 항목: 반·번호·이름, 고른 역할, 현장 미션 사진과 글, 출석 확인 시각.
이용 목적: 현장체험학습 진행과 안전 확인, 담임 선생님의 생활기록부 기재 참고. 그 밖의 목적으로 쓰지 않소.
내 기록은 나와 담임 선생님, 담당 선생님만 볼 수 있고 다른 학생에게는 보이지 않소. 기록은 이번 학년도가 끝나면 지우오.',
  class_count smallint not null default 7 check (class_count between 1 and 20),
  max_num smallint not null default 40 check (max_num between 1 and 99),
  role_cap smallint not null default 3 check (role_cap between 1 and 40),
  min_diary smallint not null default 40 check (min_diary between 0 and 500),
  min_reflect smallint not null default 80 check (min_reflect between 0 and 1000),
  role_change_until timestamptz not null default ((date_trunc('day', now() at time zone 'Asia/Seoul') + interval '29 days 23 hours 59 minutes') at time zone 'Asia/Seoul'),
  mission_open_at timestamptz not null default ((date_trunc('day', now() at time zone 'Asia/Seoul') + interval '30 days 9 hours') at time zone 'Asia/Seoul'),
  ending_open_at timestamptz not null default ((date_trunc('day', now() at time zone 'Asia/Seoul') + interval '30 days 11 hours 30 minutes') at time zone 'Asia/Seoul'),
  mission_close_at timestamptz not null default ((date_trunc('day', now() at time zone 'Asia/Seoul') + interval '30 days 18 hours') at time zone 'Asia/Seoul'),
  ending_close_at timestamptz not null default ((date_trunc('day', now() at time zone 'Asia/Seoul') + interval '30 days 18 hours') at time zone 'Asia/Seoul'),
  join_code text not null default upper(substr(md5(gen_random_uuid()::text), 1, 6)) check (join_code ~ '^[A-Z0-9]{4,12}$'),
  auth_mode text not null default 'code' check (auth_mode in ('code', 'google')),
  google_domain text check (google_domain is null or google_domain ~ '^[a-z0-9.-]+\.[a-z]{2,}$'),
  setup_code text default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  schema_version smallint not null default 1
);
insert into public.gp_settings default values;

create table public.gp_staff (
  id uuid primary key default gen_random_uuid(),
  login_id text not null unique check (login_id ~ '^[a-z0-9_.-]{3,30}$'),
  pw_hash text,
  email text unique check (email is null or email = lower(email)),
  name text not null check (char_length(name) between 1 and 20),
  kind text not null check (kind in ('admin', 'homeroom')),
  classes smallint[] not null default '{}',
  fails smallint not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now()
);

create table public.gp_roles (
  id text primary key check (id ~ '^[a-z0-9_-]{2,30}$'),
  sort smallint not null default 0,
  enabled boolean not null default true,
  name text not null check (char_length(name) between 1 and 30),
  person text not null check (char_length(person) between 1 and 20),
  seal text not null default '人' check (char_length(seal) between 1 and 2),
  intro text not null default '' check (char_length(intro) <= 200),
  career text not null default '' check (char_length(career) <= 100),
  letter jsonb not null default '[]'::jsonb,
  img boolean not null default false,
  updated_at timestamptz not null default now()
);

create table public.gp_missions (
  role_id text not null references public.gp_roles(id) on delete cascade,
  n smallint not null check (n between 1 and 3),
  place_key text not null,
  place text not null check (char_length(place) between 1 and 60),
  area text not null check (area in ('궁', '박물관')),
  clue text not null default '' check (char_length(clue) <= 600),
  photo text not null default '' check (char_length(photo) <= 300),
  diary text not null default '' check (char_length(diary) <= 400),
  primary key (role_id, n)
);

create table public.gp_endings (
  role_id text primary key references public.gp_roles(id) on delete cascade,
  photo_mission smallint not null default 1 check (photo_mission between 1 and 3),
  body jsonb not null default '{"then": [], "now": "", "prompt": ""}'::jsonb
);

create table public.gp_students (
  id uuid primary key default gen_random_uuid(),
  class_no smallint not null check (class_no between 0 and 20),
  num smallint not null check (num between 1 and 99),
  name text not null check (char_length(name) between 1 and 20),
  pin_hash text,
  email text unique,
  staff_id uuid unique references public.gp_staff(id) on delete cascade,   -- 교사 체험용(0반)
  role_id text references public.gp_roles(id) on delete set null,
  role_at timestamptz,
  checkin_at timestamptz,
  checkout_at timestamptz,
  fails smallint not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (class_no, num)
);
create index gp_students_class_role on public.gp_students(class_no, role_id);

-- 로그인한 기기(Supabase 사용자) → 학생 또는 교사. 한 사람이 여러 기기로 들어올 수 있다.
create table public.gp_bind (
  uid uuid primary key references auth.users(id) on delete cascade,
  kind text not null check (kind in ('student', 'staff')),
  ref uuid not null,
  created_at timestamptz not null default now()
);
create index gp_bind_ref on public.gp_bind(ref);

-- 미션 기록. 저장할 때의 장소·질문을 함께 남겨, 나중에 미션 문구를 고쳐도 답과 질문이 어긋나지 않는다.
create table public.gp_entries (
  student_id uuid not null references public.gp_students(id) on delete cascade,
  mission smallint not null check (mission between 1 and 3),
  role_id text,
  place text,
  question text,
  photo_path text,
  diary text check (char_length(diary) <= 2000),
  updated_at timestamptz not null default now(),
  primary key (student_id, mission)
);

create table public.gp_final (
  student_id uuid primary key references public.gp_students(id) on delete cascade,
  note text check (char_length(note) <= 1000),
  note_prompt text,
  note_at timestamptz,
  reflection text check (char_length(reflection) <= 3000),
  reflection_at timestamptz
);

create table public.gp_groups (
  code text primary key check (code ~ '^[0-9]{4}$'),
  class_no smallint not null,
  created_at timestamptz not null default now()
);
create table public.gp_group_members (
  student_id uuid primary key references public.gp_students(id) on delete cascade,
  code text not null references public.gp_groups(code) on delete cascade,
  joined_at timestamptz not null default now()
);
create index gp_group_members_code on public.gp_group_members(code);

-- 로그인 실패 기록(같은 기기에서 짧은 시간에 많이 틀리면 잠시 막는다)
create table public.gp_login_fail (
  uid uuid not null,
  at timestamptz not null default now()
);
create index gp_login_fail_uid on public.gp_login_fail(uid, at);

do $$
declare t text;
begin
  foreach t in array array['gp_settings','gp_staff','gp_roles','gp_missions','gp_endings','gp_students','gp_bind',
                           'gp_entries','gp_final','gp_groups','gp_group_members','gp_login_fail'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;
-- 정책 없음: 모든 읽기·쓰기는 아래 security definer 함수로만 한다.

-- ---------------------------------------------------------------- 안쪽 도우미
create or replace function public.gp_cfg()
returns public.gp_settings language sql stable security definer set search_path = '' as $$
  select * from public.gp_settings limit 1
$$;

-- 구글로 로그인한 경우 그 이메일(소문자). 아니면 null.
create or replace function public.gp_google_email()
returns text language sql stable security definer set search_path = '' as $$
  select lower(u.email) from auth.users u
  where u.id = (select auth.uid()) and u.email is not null
    and exists (select 1 from auth.identities i where i.user_id = u.id and i.provider = 'google')
$$;

-- 구글 로그인 학생이 허용된 학교 도메인인가
create or replace function public.gp_google_ok()
returns boolean language sql stable security definer set search_path = '' as $$
  select e is not null and (d is null or e like '%@' || d)
  from (select public.gp_google_email() e, (public.gp_cfg()).google_domain d) x
$$;

create or replace function public.gp_my_staff()
returns public.gp_staff language sql stable security definer set search_path = '' as $$
  select s.* from public.gp_staff s
  where s.id = (select b.ref from public.gp_bind b where b.uid = (select auth.uid()) and b.kind = 'staff')
     or (s.email is not null and s.email = public.gp_google_email())
  limit 1
$$;

-- 지금 기기의 학생 id. 교사는 체험용 학생(0반)이 있으면 그것.
create or replace function public.gp_my_sid()
returns uuid language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select b.ref from public.gp_bind b where b.uid = (select auth.uid()) and b.kind = 'student'),
    (select st.id from public.gp_students st where st.staff_id is not null and st.staff_id = (public.gp_my_staff()).id),
    (select st.id from public.gp_students st
      where (public.gp_cfg()).auth_mode = 'google' and st.email is not null and st.email = public.gp_google_email()))
$$;

create or replace function public.gp_is_tester(p_sid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.gp_students where id = p_sid and staff_id is not null)
$$;

-- 미션 사진·일기를 쓸 수 있는 때인가(체험용은 언제나)
create or replace function public.gp_can_write(p_sid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_sid is not null and (public.gp_is_tester(p_sid) or exists (
    select 1 from public.gp_settings c where now() between c.mission_open_at and c.mission_close_at))
$$;

-- 엔딩 한마디·소감을 쓸 수 있는 때인가
create or replace function public.gp_can_final(p_sid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_sid is not null and (public.gp_is_tester(p_sid) or exists (
    select 1 from public.gp_settings c where now() between c.ending_open_at and greatest(c.ending_close_at, c.mission_close_at)))
$$;

-- 이 학생 기록을 볼 수 있는 교사인가(관리자: 전체, 담임: 맡은 반, 체험용: 본인)
create or replace function public.gp_can_view(p_sid uuid)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare st public.gp_staff; s public.gp_students;
begin
  st := public.gp_my_staff();
  if st.id is null or p_sid is null then return false; end if;
  select * into s from public.gp_students where id = p_sid;
  if s.id is null then return false; end if;
  if st.kind = 'admin' then return true; end if;
  if s.staff_id is not null then return s.staff_id = st.id; end if;
  return s.class_no = any(st.classes);
end $$;

create or replace function public.gp_can_view_class(p_class smallint)
returns boolean language sql stable security definer set search_path = '' as $$
  select st.id is not null and (st.kind = 'admin' or p_class = any(st.classes))
  from (select (public.gp_my_staff()).*) st
$$;

create or replace function public.gp_require_staff()
returns public.gp_staff language plpgsql stable security definer set search_path = '' as $$
declare st public.gp_staff;
begin
  st := public.gp_my_staff();
  if st.id is null then raise exception 'not_staff' using errcode = '42501'; end if;
  return st;
end $$;

create or replace function public.gp_require_admin()
returns public.gp_staff language plpgsql stable security definer set search_path = '' as $$
declare st public.gp_staff;
begin
  st := public.gp_my_staff();
  if st.id is null or st.kind <> 'admin' then raise exception 'not_admin' using errcode = '42501'; end if;
  return st;
end $$;

-- 사진 경로: <학생 id>/m<번호>-<시각>.jpg
create or replace function public.gp_folder_sid(p_name text)
returns uuid language sql immutable set search_path = '' as $$
  select case when split_part(p_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    then split_part(p_name, '/', 1)::uuid end
$$;

create or replace function public.gp_photo_write_ok(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_folder_sid(p_name) is not null
     and public.gp_folder_sid(p_name) = public.gp_my_sid()
     and public.gp_can_write(public.gp_my_sid())
     and p_name ~ '^[0-9a-f-]{36}/m[1-3]-[0-9]{10,16}\.jpg$', false)
$$;

create or replace function public.gp_photo_read_ok(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_folder_sid(p_name) is not null and (
    public.gp_folder_sid(p_name) = public.gp_my_sid() or public.gp_can_view(public.gp_folder_sid(p_name))), false)
$$;

create or replace function public.gp_photo_delete_ok(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(public.gp_photo_write_ok(p_name)
      or (public.gp_folder_sid(p_name) is not null and coalesce((public.gp_my_staff()).kind = 'admin', false))
      or (public.gp_folder_sid(p_name) is not null and public.gp_can_view(public.gp_folder_sid(p_name))), false)
$$;

-- 실패 기록·확인: 같은 기기에서 10분에 15번 넘게 틀리면 잠시 막는다.
create or replace function public.gp_too_many_fails()
returns boolean language sql stable security definer set search_path = '' as $$
  select count(*) >= 15 from public.gp_login_fail where uid = (select auth.uid()) and at > now() - interval '10 minutes'
$$;
create or replace function public.gp_note_fail()
returns void language sql security definer set search_path = '' as $$
  insert into public.gp_login_fail(uid) values ((select auth.uid()));
  delete from public.gp_login_fail where at < now() - interval '1 day';
$$;

create or replace function public.gp_norm(p text)
returns text language sql immutable set search_path = '' as $$
  select regexp_replace(lower(coalesce(p, '')), '\s', '', 'g')
$$;

create or replace function public.gp_bind_me(p_kind text, p_ref uuid)
returns void language sql security definer set search_path = '' as $$
  insert into public.gp_bind(uid, kind, ref) values ((select auth.uid()), p_kind, p_ref)
  on conflict (uid) do update set kind = excluded.kind, ref = excluded.ref, created_at = now();
$$;

-- ---------------------------------------------------------------- 누구나(로그인 전)
-- 화면에 보여 줄 행사 정보. 입장 코드·설치 코드는 내보내지 않는다.
create or replace function public.gp_public()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'school_name', c.school_name, 'event_label', c.event_label, 'meet_text', c.meet_text, 'museum_time', c.museum_time,
    'rules', c.rules, 'privacy', c.privacy, 'class_count', c.class_count, 'max_num', c.max_num, 'role_cap', c.role_cap,
    'min_diary', c.min_diary, 'min_reflect', c.min_reflect,
    'role_change_until', c.role_change_until, 'mission_open_at', c.mission_open_at, 'ending_open_at', c.ending_open_at,
    'mission_close_at', c.mission_close_at, 'ending_close_at', c.ending_close_at,
    'auth_mode', c.auth_mode, 'google_domain', c.google_domain,
    'setup_needed', c.setup_code is not null and not exists (select 1 from public.gp_staff where kind = 'admin'),
    'now', now())
  from public.gp_settings c
$$;

-- 역할·편지·미션(공개 내용). 엔딩은 넣지 않는다.
create or replace function public.gp_content()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'sort', r.sort, 'enabled', r.enabled, 'name', r.name, 'person', r.person, 'seal', r.seal,
    'intro', r.intro, 'career', r.career, 'letter', r.letter, 'img', r.img,
    'missions', (select coalesce(jsonb_agg(jsonb_build_object('n', m.n, 'place_key', m.place_key, 'place', m.place, 'area', m.area,
      'clue', m.clue, 'photo', m.photo, 'diary', m.diary) order by m.n), '[]'::jsonb) from public.gp_missions m where m.role_id = r.id)
  ) order by r.sort, r.id), '[]'::jsonb)
  from public.gp_roles r
  where r.enabled or exists (select 1 from public.gp_students s where s.role_id = r.id and s.id = public.gp_my_sid())
     or coalesce((public.gp_my_staff()).id is not null, false)
$$;

-- ---------------------------------------------------------------- 로그인
-- 처음 설치한 뒤 첫 관리자 만들기(설치 코드가 맞을 때 한 번만)
create or replace function public.gp_setup(p_code text, p_login_id text, p_name text, p_pw text)
returns text language plpgsql security definer set search_path = '' as $$
declare c public.gp_settings; v_id uuid;
begin
  if (select auth.uid()) is null then raise exception 'no_session'; end if;
  select * into c from public.gp_settings for update;
  if exists (select 1 from public.gp_staff where kind = 'admin') or c.setup_code is null then return 'already'; end if;
  if public.gp_too_many_fails() then return 'slow_down'; end if;
  if upper(btrim(coalesce(p_code, ''))) <> c.setup_code then perform public.gp_note_fail(); return 'bad_code'; end if;
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

-- 교사: 아이디·비밀번호 → 이 기기를 교사로 연결. ok | mismatch | locked | slow_down
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
  update public.gp_staff set pw_hash = extensions.crypt(p_new, extensions.gen_salt('bf', 8)) where id = st.id;
  return 'ok';
end $$;

create or replace function public.gp_logout()
returns void language sql security definer set search_path = '' as $$
  delete from public.gp_bind where uid = (select auth.uid());
$$;

-- 학생(입장 코드 방식): 입장 코드 + 반·번호·이름 + 4자리 비밀번호.
-- 처음이면 새로 만들고(new), 있으면 이름·비밀번호를 확인해 이 기기를 연결한다(ok).
-- 실패: bad_join | mismatch | locked | slow_down | google_only | bad_class | bad_num | bad_name | bad_pin
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
  if s.fails >= 5 then return 'locked'; end if;
  if public.gp_norm(s.name) <> public.gp_norm(v_name) or s.email is not null then
    update public.gp_students set fails = fails + 1 where id = s.id;
    perform public.gp_note_fail();
    return 'mismatch';
  end if;
  if s.pin_hash is null then          -- 담임이 비밀번호를 지운 학생: 이번에 새로 정한다
    update public.gp_students set pin_hash = extensions.crypt(p_pin, extensions.gen_salt('bf', 6)), fails = 0, updated_at = now() where id = s.id;
  elsif s.pin_hash <> extensions.crypt(p_pin, s.pin_hash) then
    update public.gp_students set fails = fails + 1 where id = s.id;
    perform public.gp_note_fail();
    return 'mismatch';
  else
    update public.gp_students set fails = 0 where id = s.id;
  end if;
  perform public.gp_bind_me('student', s.id);
  return 'ok';
end $$;

-- 학생(구글 방식): 학교 구글 계정으로 들어와 반·번호·이름 등록. ok | taken | not_school | code_only | bad_*
create or replace function public.gp_student_google(p_class smallint, p_num smallint, p_name text)
returns text language plpgsql security definer set search_path = '' as $$
declare c public.gp_settings; e text; s public.gp_students; v_name text := btrim(coalesce(p_name, ''));
begin
  c := public.gp_cfg();
  if c.auth_mode <> 'google' then return 'code_only'; end if;
  if not public.gp_google_ok() then return 'not_school'; end if;
  e := public.gp_google_email();
  if p_class is null or p_class not between 1 and c.class_count then return 'bad_class'; end if;
  if p_num is null or p_num not between 1 and c.max_num then return 'bad_num'; end if;
  if char_length(v_name) not between 1 and 20 then return 'bad_name'; end if;
  select * into s from public.gp_students where email = e for update;
  if exists (select 1 from public.gp_students where class_no = p_class and num = p_num and id is distinct from s.id) then return 'taken'; end if;
  if s.id is null then
    insert into public.gp_students(class_no, num, name, email) values (p_class, p_num, v_name, e) returning * into s;
  else
    update public.gp_students set class_no = p_class, num = p_num, name = v_name, updated_at = now(),
      role_id = case when class_no = p_class then role_id end, role_at = case when class_no = p_class then role_at end
    where id = s.id;
  end if;
  perform public.gp_bind_me('student', s.id);
  return 'ok';
end $$;

-- 학생이 자기 반·번호·이름 고치기(반을 바꾸면 역할이 풀린다). ok | taken | bad_*
create or replace function public.gp_student_update(p_class smallint, p_num smallint, p_name text)
returns text language plpgsql security definer set search_path = '' as $$
declare c public.gp_settings; s public.gp_students; v_name text := btrim(coalesce(p_name, ''));
begin
  c := public.gp_cfg();
  select * into s from public.gp_students where id = public.gp_my_sid() for update;
  if s.id is null then raise exception 'not_registered'; end if;
  if s.staff_id is not null then return 'ok'; end if;
  if p_class is null or p_class not between 1 and c.class_count then return 'bad_class'; end if;
  if p_num is null or p_num not between 1 and c.max_num then return 'bad_num'; end if;
  if char_length(v_name) not between 1 and 20 then return 'bad_name'; end if;
  if exists (select 1 from public.gp_students where class_no = p_class and num = p_num and id <> s.id) then return 'taken'; end if;
  update public.gp_students set class_no = p_class, num = p_num, name = v_name, updated_at = now(),
    role_id = case when class_no = p_class then role_id end, role_at = case when class_no = p_class then role_at end
  where id = s.id;
  if s.class_no <> p_class then delete from public.gp_group_members where student_id = s.id; end if;
  return 'ok';
end $$;

-- 로그인 직후 내 정보
create or replace function public.gp_me()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare st public.gp_staff; s public.gp_students;
begin
  st := public.gp_my_staff();
  select * into s from public.gp_students where id = public.gp_my_sid();
  return jsonb_build_object(
    'staff', case when st.id is null then null else jsonb_build_object('id', st.id, 'name', st.name, 'kind', st.kind,
      'classes', to_jsonb(st.classes), 'login_id', st.login_id) end,
    'student', case when s.id is null then null else jsonb_build_object('id', s.id, 'class_no', s.class_no, 'num', s.num,
      'name', s.name, 'role_id', s.role_id, 'checkin_at', s.checkin_at, 'checkout_at', s.checkout_at,
      'tester', s.staff_id is not null) end,
    'google', public.gp_google_email(),
    'now', now());
end $$;

-- ---------------------------------------------------------------- 학생
create or replace function public.gp_role_counts(p_class smallint default null)
returns table(role_id text, n int) language plpgsql stable security definer set search_path = '' as $$
declare v_class smallint;
begin
  if p_class is not null and public.gp_can_view_class(p_class) then v_class := p_class;
  else select s.class_no into v_class from public.gp_students s where s.id = public.gp_my_sid();
  end if;
  if v_class is null or v_class = 0 then return; end if;
  return query select s.role_id, count(*)::int from public.gp_students s
    where s.class_no = v_class and s.role_id is not null group by s.role_id;
end $$;

-- 역할 고르기: 반마다 역할별 정원, 마감 전까지 바꿀 수 있다(체험용은 언제나·정원 없음). ok | full
create or replace function public.gp_choose_role(p_role text)
returns text language plpgsql security definer set search_path = '' as $$
declare s public.gp_students; c public.gp_settings; cnt int;
begin
  c := public.gp_cfg();
  select * into s from public.gp_students where id = public.gp_my_sid() for update;
  if s.id is null then raise exception 'not_registered'; end if;
  if not exists (select 1 from public.gp_roles where id = p_role and enabled) then raise exception 'bad_role'; end if;
  if s.role_id = p_role then return 'ok'; end if;
  if s.staff_id is null then
    if now() > c.role_change_until then raise exception 'role_closed'; end if;
    perform pg_advisory_xact_lock(hashtext('gp_role:' || s.class_no || ':' || p_role));
    select count(*) into cnt from public.gp_students where class_no = s.class_no and role_id = p_role and id <> s.id;
    if cnt >= c.role_cap then return 'full'; end if;
  else
    delete from public.gp_entries where student_id = s.id;      -- 체험용은 역할을 바꾸면 기록을 비운다
  end if;
  update public.gp_students set role_id = p_role, role_at = now(), updated_at = now() where id = s.id;
  delete from public.gp_group_members where student_id = s.id;
  return 'ok';
end $$;

create or replace function public.gp_my_records()
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'entries', (select coalesce(jsonb_agg(jsonb_build_object('mission', e.mission, 'photo_path', e.photo_path, 'diary', e.diary,
      'updated_at', e.updated_at) order by e.mission), '[]'::jsonb) from public.gp_entries e where e.student_id = public.gp_my_sid()),
    'final', (select jsonb_build_object('note', f.note, 'note_at', f.note_at, 'reflection', f.reflection, 'reflection_at', f.reflection_at)
      from public.gp_final f where f.student_id = public.gp_my_sid()))
$$;

-- 미션 질문을 기록에 함께 남기는 도우미
create or replace function public.gp_entry_upsert(p_sid uuid, p_mission smallint)
returns void language plpgsql security definer set search_path = '' as $$
declare s public.gp_students; m public.gp_missions;
begin
  select * into s from public.gp_students where id = p_sid;
  select * into m from public.gp_missions where role_id = s.role_id and n = p_mission;
  if m.role_id is null then raise exception 'no_role'; end if;
  insert into public.gp_entries(student_id, mission, role_id, place, question)
  values (p_sid, p_mission, s.role_id, m.place, m.diary)
  on conflict (student_id, mission) do update set role_id = excluded.role_id, place = excluded.place, question = excluded.question;
end $$;

-- 일기 자동 저장(입력을 멈추면 앱이 부른다). 저장한 시각을 돌려준다.
create or replace function public.gp_save_diary(p_mission smallint, p_diary text)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare sid uuid := public.gp_my_sid(); t timestamptz := now();
begin
  if sid is null then raise exception 'not_registered'; end if;
  if not public.gp_can_write(sid) then raise exception 'not_open'; end if;
  if p_mission not between 1 and 3 then raise exception 'bad_mission'; end if;
  perform public.gp_entry_upsert(sid, p_mission);
  update public.gp_entries set diary = left(btrim(coalesce(p_diary, '')), 2000), updated_at = t
  where student_id = sid and mission = p_mission;
  return t;
end $$;

-- 사진 저장(올린 직후 앱이 부른다). 바꾸기 전 사진 경로를 돌려준다(앱이 지운다).
create or replace function public.gp_save_photo(p_mission smallint, p_path text)
returns text language plpgsql security definer set search_path = '' as $$
declare sid uuid := public.gp_my_sid(); old text;
begin
  if sid is null then raise exception 'not_registered'; end if;
  if not public.gp_can_write(sid) then raise exception 'not_open'; end if;
  if p_mission not between 1 and 3 then raise exception 'bad_mission'; end if;
  if p_path is null or p_path !~ ('^' || sid::text || '/m' || p_mission || '-[0-9]{10,16}\.jpg$') then raise exception 'bad_path'; end if;
  perform public.gp_entry_upsert(sid, p_mission);
  select photo_path into old from public.gp_entries where student_id = sid and mission = p_mission;
  update public.gp_entries set photo_path = p_path, updated_at = now() where student_id = sid and mission = p_mission;
  return case when old is distinct from p_path then old end;
end $$;

create or replace function public.gp_save_note(p_text text)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare sid uuid := public.gp_my_sid(); s public.gp_students; e public.gp_endings; t timestamptz := now();
begin
  if sid is null then raise exception 'not_registered'; end if;
  if not public.gp_can_final(sid) then raise exception 'ending_locked'; end if;
  select * into s from public.gp_students where id = sid;
  select * into e from public.gp_endings where role_id = s.role_id;
  insert into public.gp_final(student_id, note, note_prompt, note_at)
  values (sid, left(btrim(coalesce(p_text, '')), 1000), e.body->>'prompt', t)
  on conflict (student_id) do update set note = excluded.note, note_prompt = excluded.note_prompt, note_at = t;
  return t;
end $$;

create or replace function public.gp_save_reflection(p_text text)
returns timestamptz language plpgsql security definer set search_path = '' as $$
declare sid uuid := public.gp_my_sid(); t timestamptz := now();
begin
  if sid is null then raise exception 'not_registered'; end if;
  if not public.gp_can_final(sid) then raise exception 'ending_locked'; end if;
  insert into public.gp_final(student_id, reflection, reflection_at) values (sid, left(btrim(coalesce(p_text, '')), 3000), t)
  on conflict (student_id) do update set reflection = excluded.reflection, reflection_at = t;
  return t;
end $$;

-- 출석(in)·종례 확인(out)
create or replace function public.gp_checkin(p_kind text)
returns void language plpgsql security definer set search_path = '' as $$
declare sid uuid := public.gp_my_sid();
begin
  if sid is null then raise exception 'not_registered'; end if;
  if not public.gp_can_write(sid) and not public.gp_can_final(sid) then raise exception 'not_open'; end if;
  if p_kind = 'in' then update public.gp_students set checkin_at = coalesce(checkin_at, now()) where id = sid;
  elsif p_kind = 'out' then update public.gp_students set checkout_at = coalesce(checkout_at, now()) where id = sid;
  else raise exception 'bad_kind'; end if;
end $$;

-- 엔딩: 열리는 시각 뒤에 내 역할만. 교사는 아무 역할이나 미리 볼 수 있다.
create or replace function public.gp_get_ending(p_role text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare sid uuid; s public.gp_students; v_role text; e public.gp_endings;
begin
  if p_role is not null and (public.gp_my_staff()).id is not null then
    v_role := p_role;
  else
    sid := public.gp_my_sid();
    select * into s from public.gp_students where id = sid;
    if s.role_id is null then raise exception 'no_role'; end if;
    if not public.gp_is_tester(sid) and now() < (public.gp_cfg()).ending_open_at then raise exception 'ending_locked'; end if;
    v_role := s.role_id;
  end if;
  select * into e from public.gp_endings where role_id = v_role;
  if e.role_id is null then return jsonb_build_object('role_id', v_role, 'photo_mission', 1, 'body', '{"then": [], "now": "", "prompt": ""}'::jsonb); end if;
  return jsonb_build_object('role_id', e.role_id, 'photo_mission', e.photo_mission, 'body', e.body);
end $$;

-- ---------------------------------------------------------------- 함께 다니기(역할 마감 뒤 ~ 미션 마감 전, 같은 반 최대 3명)
create or replace function public.gp_group_open()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.gp_is_tester(public.gp_my_sid()) or exists (
    select 1 from public.gp_settings c where now() > c.role_change_until and now() < c.mission_close_at)
$$;

create or replace function public.gp_group_mine()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare s public.gp_students; g public.gp_groups;
begin
  select * into s from public.gp_students where id = public.gp_my_sid();
  if s.id is null then return null; end if;
  select gr.* into g from public.gp_group_members m join public.gp_groups gr on gr.code = m.code where m.student_id = s.id;
  if g.code is null then return null; end if;
  if g.class_no <> s.class_no then
    delete from public.gp_group_members where student_id = s.id;
    delete from public.gp_groups where code = g.code and not exists (select 1 from public.gp_group_members where code = g.code);
    return null;
  end if;
  return jsonb_build_object('code', g.code, 'members', (
    select coalesce(jsonb_agg(jsonb_build_object('name', x.name, 'role_id', x.role_id, 'me', x.id = s.id) order by m.joined_at), '[]'::jsonb)
    from public.gp_group_members m join public.gp_students x on x.id = m.student_id
    where m.code = g.code and x.class_no = g.class_no));
end $$;

create or replace function public.gp_group_create()
returns text language plpgsql security definer set search_path = '' as $$
declare s public.gp_students; c text; i int := 0;
begin
  if not public.gp_group_open() then raise exception 'group_closed'; end if;
  select * into s from public.gp_students where id = public.gp_my_sid() for update;
  if s.id is null then raise exception 'not_registered'; end if;
  if s.role_id is null then raise exception 'no_role'; end if;
  if exists (select 1 from public.gp_group_members where student_id = s.id) then raise exception 'in_group'; end if;
  loop
    c := lpad((floor(random() * 10000))::int::text, 4, '0');
    exit when not exists (select 1 from public.gp_groups where code = c);
    i := i + 1; if i > 50 then raise exception 'no_code'; end if;
  end loop;
  insert into public.gp_groups(code, class_no) values (c, s.class_no);
  insert into public.gp_group_members(student_id, code) values (s.id, c);
  return c;
end $$;

-- ok | no_group | other_class | full
create or replace function public.gp_group_join(p_code text)
returns text language plpgsql security definer set search_path = '' as $$
declare s public.gp_students; g public.gp_groups; n int;
begin
  if not public.gp_group_open() then raise exception 'group_closed'; end if;
  select * into s from public.gp_students where id = public.gp_my_sid() for update;
  if s.id is null then raise exception 'not_registered'; end if;
  if s.role_id is null then raise exception 'no_role'; end if;
  if exists (select 1 from public.gp_group_members where student_id = s.id) then raise exception 'in_group'; end if;
  if p_code is null or p_code !~ '^[0-9]{4}$' then return 'no_group'; end if;
  perform pg_advisory_xact_lock(hashtext('gp_group:' || p_code));
  select * into g from public.gp_groups where code = p_code;
  if g.code is null then return 'no_group'; end if;
  if g.class_no <> s.class_no then return 'other_class'; end if;
  select count(*) into n from public.gp_group_members m join public.gp_students x on x.id = m.student_id
    where m.code = g.code and x.class_no = g.class_no;
  if n >= 3 then return 'full'; end if;
  insert into public.gp_group_members(student_id, code) values (s.id, g.code);
  return 'ok';
end $$;

create or replace function public.gp_group_leave()
returns void language plpgsql security definer set search_path = '' as $$
declare c text;
begin
  delete from public.gp_group_members where student_id = public.gp_my_sid() returning code into c;
  if c is not null then
    delete from public.gp_groups where code = c and not exists (select 1 from public.gp_group_members where code = c);
  end if;
end $$;

-- ---------------------------------------------------------------- 교사(담임: 맡은 반, 관리자: 전체)
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
    s.fails >= 5, s.pin_hash is not null, s.email is not null
  from public.gp_students s where s.class_no = p_class and s.staff_id is null order by s.num, s.name;
end $$;

create or replace function public.gp_student_detail(p_sid uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare s public.gp_students;
begin
  if not public.gp_can_view(p_sid) then raise exception 'not_staff' using errcode = '42501'; end if;
  select * into s from public.gp_students where id = p_sid;
  return jsonb_build_object(
    'student', jsonb_build_object('id', s.id, 'class_no', s.class_no, 'num', s.num, 'name', s.name, 'role_id', s.role_id,
      'checkin_at', s.checkin_at, 'checkout_at', s.checkout_at, 'tester', s.staff_id is not null),
    'entries', (select coalesce(jsonb_agg(jsonb_build_object('mission', e.mission, 'place', e.place, 'question', e.question,
      'photo_path', e.photo_path, 'diary', e.diary, 'updated_at', e.updated_at) order by e.mission), '[]'::jsonb)
      from public.gp_entries e where e.student_id = p_sid),
    'final', (select jsonb_build_object('note', f.note, 'note_prompt', f.note_prompt, 'note_at', f.note_at,
      'reflection', f.reflection, 'reflection_at', f.reflection_at) from public.gp_final f where f.student_id = p_sid));
end $$;

-- 생기부용 내보내기(학생 한 줄). p_class가 null이면 전체(관리자만).
create or replace function public.gp_class_export(p_class smallint)
returns table(class_no smallint, num smallint, name text, role_id text, checkin_at timestamptz, checkout_at timestamptz,
  m1_place text, m1_question text, m1_photo boolean, m1_diary text,
  m2_place text, m2_question text, m2_photo boolean, m2_diary text,
  m3_place text, m3_question text, m3_photo boolean, m3_diary text,
  note text, reflection text, group_code text)
language plpgsql stable security definer set search_path = '' as $$
declare st public.gp_staff;
begin
  st := public.gp_require_staff();
  if p_class is null and st.kind <> 'admin' then raise exception 'not_admin' using errcode = '42501'; end if;
  if p_class is not null and not public.gp_can_view_class(p_class) then raise exception 'not_staff' using errcode = '42501'; end if;
  return query select s.class_no, s.num, s.name, s.role_id, s.checkin_at, s.checkout_at,
    e1.place, e1.question, e1.photo_path is not null, e1.diary,
    e2.place, e2.question, e2.photo_path is not null, e2.diary,
    e3.place, e3.question, e3.photo_path is not null, e3.diary,
    f.note, f.reflection, gm.code
  from public.gp_students s
  left join public.gp_entries e1 on e1.student_id = s.id and e1.mission = 1
  left join public.gp_entries e2 on e2.student_id = s.id and e2.mission = 2
  left join public.gp_entries e3 on e3.student_id = s.id and e3.mission = 3
  left join public.gp_final f on f.student_id = s.id
  left join public.gp_group_members gm on gm.student_id = s.id
  where s.staff_id is null and (p_class is null or s.class_no = p_class)
  order by s.class_no, s.num;
end $$;

create or replace function public.gp_class_groups(p_class smallint)
returns table(sid uuid, code text) language plpgsql stable security definer set search_path = '' as $$
begin
  if not public.gp_can_view_class(p_class) then raise exception 'not_staff' using errcode = '42501'; end if;
  return query select m.student_id, m.code from public.gp_group_members m join public.gp_students s on s.id = m.student_id
    join public.gp_groups g on g.code = m.code where s.class_no = p_class and g.class_no = p_class;
end $$;

-- 학생 비밀번호 지우기(잠김 풀기). 학생이 다음에 들어올 때 새 비밀번호를 정한다.
create or replace function public.gp_reset_pin(p_sid uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.gp_can_view(p_sid) then raise exception 'not_staff' using errcode = '42501'; end if;
  update public.gp_students set pin_hash = null, fails = 0, updated_at = now() where id = p_sid and staff_id is null;
  delete from public.gp_bind where kind = 'student' and ref = p_sid;
end $$;

-- 잘못 들어온 학생 지우기. 앱이 gp_student_detail의 사진을 보관함에서 먼저 지운 뒤 부른다. 남은 사진 경로를 돌려준다.
create or replace function public.gp_delete_student(p_sid uuid)
returns text[] language plpgsql security definer set search_path = '' as $$
declare paths text[];
begin
  if not public.gp_can_view(p_sid) then raise exception 'not_staff' using errcode = '42501'; end if;
  select coalesce(array_agg(photo_path) filter (where photo_path is not null), '{}') into paths from public.gp_entries where student_id = p_sid;
  delete from public.gp_bind where kind = 'student' and ref = p_sid;
  delete from public.gp_students where id = p_sid;
  return paths;
end $$;

-- 교사 체험: 0반 체험용 학생을 만들어 학생 화면을 시간 제한 없이 해 본다.
create or replace function public.gp_try_student()
returns void language plpgsql security definer set search_path = '' as $$
declare st public.gp_staff; n smallint;
begin
  st := public.gp_require_staff();
  if exists (select 1 from public.gp_students where staff_id = st.id) then return; end if;
  perform pg_advisory_xact_lock(hashtext('gp_tester'));
  select coalesce(max(num), 0) + 1 into n from public.gp_students where class_no = 0;
  insert into public.gp_students(class_no, num, name, staff_id) values (0, n, left(st.name, 14) || '(체험)', st.id);
end $$;

-- ---------------------------------------------------------------- 관리자
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
      'locked', s.locked_until is not null and s.locked_until > now()) order by s.kind, s.login_id), '[]'::jsonb) from public.gp_staff s),
    'counts', jsonb_build_object(
      'students', (select count(*) from public.gp_students where staff_id is null),
      'entries', (select count(*) from public.gp_entries e join public.gp_students s on s.id = e.student_id where s.staff_id is null),
      'photos', (select count(*) from storage.objects where bucket_id = 'gp-photos')));
end $$;

create or replace function public.gp_admin_save_settings(p jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare c public.gp_settings;
begin
  perform public.gp_require_admin();
  select * into c from public.gp_settings for update;
  c.school_name := left(btrim(coalesce(p->>'school_name', c.school_name)), 60);
  c.event_label := left(btrim(coalesce(p->>'event_label', c.event_label)), 80);
  c.meet_text := left(btrim(coalesce(p->>'meet_text', c.meet_text)), 200);
  c.museum_time := left(btrim(coalesce(p->>'museum_time', c.museum_time)), 20);
  c.privacy := left(coalesce(p->>'privacy', c.privacy), 2000);
  if p ? 'rules' then
    if jsonb_typeof(p->'rules') <> 'array' or jsonb_array_length(p->'rules') > 20 then return 'bad_rules'; end if;
    c.rules := p->'rules';
  end if;
  c.class_count := coalesce((p->>'class_count')::smallint, c.class_count);
  c.max_num := coalesce((p->>'max_num')::smallint, c.max_num);
  c.role_cap := coalesce((p->>'role_cap')::smallint, c.role_cap);
  c.min_diary := coalesce((p->>'min_diary')::smallint, c.min_diary);
  c.min_reflect := coalesce((p->>'min_reflect')::smallint, c.min_reflect);
  c.role_change_until := coalesce((p->>'role_change_until')::timestamptz, c.role_change_until);
  c.mission_open_at := coalesce((p->>'mission_open_at')::timestamptz, c.mission_open_at);
  c.ending_open_at := coalesce((p->>'ending_open_at')::timestamptz, c.ending_open_at);
  c.mission_close_at := coalesce((p->>'mission_close_at')::timestamptz, c.mission_close_at);
  c.ending_close_at := coalesce((p->>'ending_close_at')::timestamptz, c.ending_close_at);
  if not (c.mission_open_at < c.mission_close_at and c.ending_open_at between c.mission_open_at and c.mission_close_at
          and c.ending_close_at >= c.mission_close_at and c.role_change_until <= c.mission_close_at) then return 'bad_time'; end if;
  if p ? 'join_code' then c.join_code := upper(btrim(p->>'join_code')); end if;
  if c.join_code !~ '^[A-Z0-9]{4,12}$' then return 'bad_join'; end if;
  if p ? 'auth_mode' then c.auth_mode := p->>'auth_mode'; end if;
  if p ? 'google_domain' then c.google_domain := nullif(lower(btrim(p->>'google_domain')), ''); end if;
  if c.auth_mode not in ('code', 'google') then return 'bad_mode'; end if;
  if c.google_domain is not null and c.google_domain !~ '^[a-z0-9.-]+\.[a-z]{2,}$' then return 'bad_domain'; end if;
  update public.gp_settings set school_name = c.school_name, event_label = c.event_label, meet_text = c.meet_text,
    museum_time = c.museum_time, privacy = c.privacy, rules = c.rules, class_count = c.class_count, max_num = c.max_num,
    role_cap = c.role_cap, min_diary = c.min_diary, min_reflect = c.min_reflect, role_change_until = c.role_change_until,
    mission_open_at = c.mission_open_at, ending_open_at = c.ending_open_at, mission_close_at = c.mission_close_at,
    ending_close_at = c.ending_close_at, join_code = c.join_code, auth_mode = c.auth_mode, google_domain = c.google_domain
  where id;
  return 'ok';
end $$;

-- 관리자 편집용 전체 내용(꺼 둔 역할·엔딩 포함)
create or replace function public.gp_admin_content()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.gp_require_admin();
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id', r.id, 'sort', r.sort, 'enabled', r.enabled, 'name', r.name, 'person', r.person, 'seal', r.seal,
    'intro', r.intro, 'career', r.career, 'letter', r.letter, 'img', r.img,
    'chosen', (select count(*) from public.gp_students s where s.role_id = r.id and s.staff_id is null),
    'missions', (select coalesce(jsonb_agg(jsonb_build_object('n', m.n, 'place_key', m.place_key, 'place', m.place, 'area', m.area,
      'clue', m.clue, 'photo', m.photo, 'diary', m.diary) order by m.n), '[]'::jsonb) from public.gp_missions m where m.role_id = r.id),
    'ending', (select jsonb_build_object('photo_mission', e.photo_mission, 'body', e.body) from public.gp_endings e where e.role_id = r.id)
  ) order by r.sort, r.id), '[]'::jsonb) from public.gp_roles r);
end $$;

-- 역할 하나(편지·미션 3개·엔딩)를 한꺼번에 저장. ok | bad_*
create or replace function public.gp_admin_save_role(p jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare v_id text := p->>'id'; m jsonb; i int := 0; museum_seen boolean := false; k text; e jsonb := nullif(p->'ending', 'null'::jsonb);
  keys text[] := array['gwanghwamun','heungnyemun','geunjeongmun','geunjeongjeon','sajeongjeon','gangnyeongjeon','gyotaejeon','amisan',
    'heumgyeonggak','jagyeongjeon','sojubang','donggung','bihyeongak','gyeonghoeru','sujeongjeon','hyangwonjeong','geoncheonggung',
    'jibokjae','museum','sinmumun','geonchunmun','yeongchumun'];
begin
  perform public.gp_require_admin();
  if v_id is null or v_id !~ '^[a-z0-9_-]{2,30}$' then return 'bad_id'; end if;
  if char_length(btrim(coalesce(p->>'name', ''))) not between 1 and 30 then return 'bad_name'; end if;
  if char_length(btrim(coalesce(p->>'person', ''))) not between 1 and 20 then return 'bad_person'; end if;
  if jsonb_typeof(p->'letter') <> 'array' or jsonb_array_length(p->'letter') > 8 then return 'bad_letter'; end if;
  if jsonb_typeof(p->'missions') <> 'array' or jsonb_array_length(p->'missions') <> 3 then return 'bad_missions'; end if;
  for m in select * from jsonb_array_elements(p->'missions') loop
    k := m->>'place_key';
    if not (k = any(keys)) then return 'bad_place'; end if;
    if char_length(btrim(coalesce(m->>'place', ''))) = 0 or char_length(btrim(coalesce(m->>'diary', ''))) = 0 then return 'empty_mission'; end if;
    if k = 'museum' then museum_seen := true; elsif museum_seen then return 'museum_order'; end if;
  end loop;
  if e is not null and (jsonb_typeof(e->'body'->'then') <> 'array'
     or (e->'body'->'old' is not null and coalesce(e->'body'->'old'->>'src', '') !~ '^then/[A-Za-z0-9_-]+\.(jpg|webp|png)$')) then return 'bad_ending'; end if;
  insert into public.gp_roles(id, sort, enabled, name, person, seal, intro, career, letter, img, updated_at)
  values (v_id, coalesce((p->>'sort')::smallint, 0), coalesce((p->>'enabled')::boolean, true), btrim(p->>'name'), btrim(p->>'person'),
    left(coalesce(nullif(btrim(p->>'seal'), ''), '人'), 2), left(coalesce(p->>'intro', ''), 200), left(coalesce(p->>'career', ''), 100),
    p->'letter', coalesce((p->>'img')::boolean, false), now())
  on conflict (id) do update set sort = excluded.sort, enabled = excluded.enabled, name = excluded.name, person = excluded.person,
    seal = excluded.seal, intro = excluded.intro, career = excluded.career, letter = excluded.letter, updated_at = now();
  for m in select * from jsonb_array_elements(p->'missions') loop
    i := i + 1;
    insert into public.gp_missions(role_id, n, place_key, place, area, clue, photo, diary)
    values (v_id, i, m->>'place_key', left(btrim(m->>'place'), 60), case when m->>'place_key' = 'museum' then '박물관' else '궁' end,
      left(coalesce(m->>'clue', ''), 600), left(coalesce(m->>'photo', ''), 300), left(coalesce(m->>'diary', ''), 400))
    on conflict (role_id, n) do update set place_key = excluded.place_key, place = excluded.place, area = excluded.area,
      clue = excluded.clue, photo = excluded.photo, diary = excluded.diary;
  end loop;
  if e is not null then
    insert into public.gp_endings(role_id, photo_mission, body)
    values (v_id, least(3, greatest(1, coalesce((e->>'photo_mission')::smallint, 1))), e->'body')
    on conflict (role_id) do update set photo_mission = excluded.photo_mission, body = excluded.body;
  end if;
  return 'ok';
end $$;

-- 역할 지우기: 고른 학생이 있으면 지우지 않는다(끄기만 할 수 있다). ok | in_use
create or replace function public.gp_admin_delete_role(p_id text)
returns text language plpgsql security definer set search_path = '' as $$
begin
  perform public.gp_require_admin();
  if exists (select 1 from public.gp_students where role_id = p_id and staff_id is null) then return 'in_use'; end if;
  delete from public.gp_roles where id = p_id;
  return 'ok';
end $$;

-- 교사 계정 만들기·고치기. password가 있으면 새로 정한다. ok | bad_* | dup_id | dup_email | last_admin
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
    insert into public.gp_staff(login_id, pw_hash, email, name, kind, classes)
    values (v_login, case when coalesce(v_pw, '') <> '' then extensions.crypt(v_pw, extensions.gen_salt('bf', 8)) end,
      v_email, btrim(p->>'name'), v_kind, v_classes);
  else
    if v_id = me.id and v_kind <> 'admin' then return 'last_admin'; end if;
    update public.gp_staff set login_id = v_login, email = v_email, name = btrim(p->>'name'), kind = v_kind, classes = v_classes,
      pw_hash = case when coalesce(v_pw, '') <> '' then extensions.crypt(v_pw, extensions.gen_salt('bf', 8)) else pw_hash end,
      fails = 0, locked_until = null
    where id = v_id;
    if coalesce(v_pw, '') <> '' and v_id <> me.id then delete from public.gp_bind where kind = 'staff' and ref = v_id; end if;
  end if;
  return 'ok';
end $$;

create or replace function public.gp_admin_delete_staff(p_id uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare me public.gp_staff;
begin
  me := public.gp_require_admin();
  if p_id = me.id then return 'self'; end if;
  delete from public.gp_bind where kind = 'staff' and ref = p_id;
  delete from public.gp_staff where id = p_id;
  return 'ok';
end $$;

-- 보관함에 있는 사진 경로 전체(기록 지우기 전에 앱이 사진부터 지운다)
create or replace function public.gp_admin_photo_paths()
returns text[] language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.gp_require_admin();
  return (select coalesce(array_agg(name), '{}') from storage.objects where bucket_id = 'gp-photos');
end $$;

-- 학생 기록 모두 지우기(학년도 말). 교사 계정·역할·미션·설정은 남는다.
create or replace function public.gp_admin_wipe(p_confirm text)
returns text language plpgsql security definer set search_path = '' as $$
begin
  perform public.gp_require_admin();
  if p_confirm is distinct from '기록 지우기' then return 'confirm'; end if;
  delete from public.gp_bind where kind = 'student';
  delete from public.gp_group_members where true;
  delete from public.gp_groups where true;
  delete from public.gp_students where true;
  delete from public.gp_login_fail where true;
  return 'ok';
end $$;

-- ---------------------------------------------------------------- 사진 보관함
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('gp-photos', 'gp-photos', false, 3145728, array['image/jpeg'])
on conflict (id) do nothing;

create policy gp_photos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'gp-photos' and public.gp_photo_write_ok(name));
create policy gp_photos_select on storage.objects for select to authenticated
  using (bucket_id = 'gp-photos' and public.gp_photo_read_ok(name));
create policy gp_photos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'gp-photos' and public.gp_photo_delete_ok(name));

-- ---------------------------------------------------------------- 실행 권한
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'gp\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- 로그인 전에도 부르는 것
grant execute on function public.gp_public(), public.gp_content() to anon, authenticated;
-- 사진 보관함 정책 안에서 쓰는 것
grant execute on function public.gp_photo_write_ok(text), public.gp_photo_read_ok(text), public.gp_photo_delete_ok(text) to authenticated;
-- 앱이 부르는 것(익명 로그인 포함 authenticated). 각 함수가 학생·교사·관리자를 다시 확인한다.
grant execute on function
  public.gp_setup(text, text, text, text), public.gp_staff_login(text, text), public.gp_staff_password(text, text), public.gp_logout(),
  public.gp_student_enter(text, smallint, smallint, text, text), public.gp_student_google(smallint, smallint, text),
  public.gp_student_update(smallint, smallint, text), public.gp_me(),
  public.gp_role_counts(smallint), public.gp_choose_role(text), public.gp_my_records(),
  public.gp_save_diary(smallint, text), public.gp_save_photo(smallint, text), public.gp_save_note(text), public.gp_save_reflection(text),
  public.gp_checkin(text), public.gp_get_ending(text),
  public.gp_group_open(), public.gp_group_mine(), public.gp_group_create(), public.gp_group_join(text), public.gp_group_leave(),
  public.gp_class_status(smallint), public.gp_student_detail(uuid), public.gp_class_export(smallint), public.gp_class_groups(smallint),
  public.gp_reset_pin(uuid), public.gp_delete_student(uuid), public.gp_try_student(),
  public.gp_admin_get(), public.gp_admin_save_settings(jsonb), public.gp_admin_content(), public.gp_admin_save_role(jsonb),
  public.gp_admin_delete_role(text), public.gp_admin_save_staff(jsonb), public.gp_admin_delete_staff(uuid),
  public.gp_admin_photo_paths(), public.gp_admin_wipe(text)
to authenticated;
