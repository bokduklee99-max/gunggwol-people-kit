-- 궁궐 사람들 키트 설치 파일 (자동 생성: node scripts/build-install.mjs — 직접 고치지 말고 schema.sql·content/를 고친다)
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
  setup_code text default upper(substr(md5(gen_random_uuid()::text), 1, 12)),     -- 첫 관리자 만들 때 한 번(12자리)
  setup_until timestamptz default now() + interval '24 hours',                 -- 설치 코드 유효 시각(지나면 new_setup_code.sql로 새로)
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
  must_change boolean not null default false,    -- 관리자가 정해 준 비밀번호: 처음 로그인 때 바꾸게 한다
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
  locked_until timestamptz,                      -- 비밀번호 5번 틀리면 15분 잠금(저절로 풀림)
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
  kind text not null default 'login',
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
  where s.id = (select b.ref from public.gp_bind b where b.uid = (select auth.uid()) and b.kind = 'staff'
                  and b.created_at > now() - interval '12 hours')   -- 교사 로그인은 12시간 뒤 끊긴다(공용 PC 대비)
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
create or replace function public.gp_note_fail(p_kind text default 'login')
returns void language sql security definer set search_path = '' as $$
  insert into public.gp_login_fail(uid, kind) values ((select auth.uid()), p_kind);
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
    'setup_needed', c.setup_code is not null and now() < c.setup_until and not exists (select 1 from public.gp_staff where kind = 'admin'),
    'setup_expired', c.setup_code is not null and now() >= c.setup_until and not exists (select 1 from public.gp_staff where kind = 'admin'),
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

create or replace function public.gp_logout()
returns void language sql security definer set search_path = '' as $$
  delete from public.gp_bind where uid = (select auth.uid());
$$;

-- 학생(입장 코드 방식): 입장 코드 + 반·번호·이름 + 4자리 비밀번호.
-- 처음이면 새로 만들고(new), 있으면 이름·비밀번호를 확인해 이 기기를 연결한다(ok).
-- 비밀번호·이름을 5번 틀리면 15분 동안 잠긴다(담임이 바로 풀 수도 있다).
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
      'classes', to_jsonb(st.classes), 'login_id', st.login_id, 'must_change', st.must_change) end,
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
    s.locked_until is not null and s.locked_until > now(), s.pin_hash is not null, s.email is not null
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
  update public.gp_students set pin_hash = null, fails = 0, locked_until = null, updated_at = now() where id = p_sid and staff_id is null;
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
      'locked', s.locked_until is not null and s.locked_until > now(), 'must_change', s.must_change) order by s.kind, s.login_id), '[]'::jsonb) from public.gp_staff s),
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

-- ---------------------------------------------------------------- 기본 내용: 경복궁 역할 14개(편지·미션·엔딩)
-- 관리자 화면 [역할·미션]에서 고치거나 끄고, 새 역할을 더할 수 있다.
create temporary table gp_seed as select x from jsonb_array_elements($gpseed$[{"id":"sumunjang","sort":1,"name":"수문장","person":"박무겸","seal":"守","intro":"궁궐의 문을 지키는 무관. 누가 드나드는지 살핀다.","career":"경찰·경호·군인","img":true,"letter":["나는 경복궁의 문을 지키는 수문장 박무겸이오.","스무 해 전 대원군 대감께서 이 궁궐을 다시 세우실 때 나는 돌을 나르던 소년이었는데, 이제는 그 문들을 지키는 사람이 되었소.","오늘은 궁궐 안의 문들을 돌며 누가 드나드는지 살피려 하오. 그대가 내 눈이 되어 주시오."],"missions":[{"place_key":"geunjeongmun","place":"근정문","area":"궁","clue":"흥례문을 지나면 나오는 두 번째 문, 근정전으로 들어가는 문이오. 문이 세 칸인데 가운데 문은 임금만 지나오.","photo":"문 세 칸이 모두 보이게 근정문을 찍으시오.","diary":"허락 없는 사람이 드나들지 못하게 이 문을 지킨다면, 문과 담의 생김새에서 좋은 점이나 어려운 점은 무엇이오?"},{"place_key":"yeongchumun","place":"영추문 (궁 안에서)","area":"궁","clue":"궁궐 서쪽 담장의 문이오. 경회루·수정전 서쪽에 있고, 관리들이 날마다 드나들던 문이라 하오. 궁 안쪽에서만 보고, 이 문으로 나가지는 마시오.","photo":"궁 안쪽에서 영추문을 찍으시오. 현판이 보이면 더 좋소.","diary":"근정문과 견주어 영추문은 생김새가 어떻게 다르오? 어째서 그렇게 지었다고 보오?"},{"place_key":"museum","place":"국립고궁박물관 · 왕실의례","area":"박물관","clue":"박물관 지하층, 나라의 큰 의례에 쓰던 물건들이 모인 곳이오.","photo":"임금의 의례에 쓰던 물건 가운데 내가 지키고 싶은 것 하나를 찍으시오.","diary":"그 물건을 지킨다면 무엇으로부터(불·도둑·습기·사람 손 같은 것) 지켜야 하오? 수문장으로서 어떻게 지키겠소?"}],"ending":{"photo_mission":2,"body":{"then":["그대가 찍은 영추문은 관리들이 날마다 드나들던 문이오.","1926년 4월, 문 앞을 지나는 전차의 진동에 석축이 무너졌고, 일제는 아예 문을 헐어 버렸소.","1975년에야 다시 세워졌지만 원래 자리보다 북쪽으로 45m쯤 비켜났고, 곁에 군부대가 들어서면서 문은 굳게 닫혔소."],"now":"2018년 12월, 영추문은 43년 만에 열렸소. 이제는 관리가 아니라 누구나 드나드는 문이 되었소.","prompt":"문을 지키던 박무겸에게, 지금 이 문을 드나드는 사람들 이야기를 전하시오.","old":{"at":1,"src":"then/e1732ec2788a.jpg","cap":"1926년 4월, 석축이 무너진 영추문","credit":"『매일신보』 1926년 4월 29일 자 · 퍼블릭 도메인"}}}},{"id":"juseo","sort":2,"name":"승정원 주서","person":"윤사겸","seal":"記","intro":"임금과 신하가 나눈 말을 한 글자도 빠짐없이 적는 기록관.","career":"기록연구사·기자·공무원","img":true,"letter":["나는 승정원의 주서 윤사겸이오.","임금께서 하시는 말씀과 신하들이 올리는 말을 한 글자도 빠짐없이 적는 것이 내 일이오. 우리가 날마다 쌓는 『승정원일기』는 이미 수천 권이 넘었소.","오늘도 붓과 종이를 챙겨 궁에 드오. 그대가 내 대신 보고 적어 주시오."],"missions":[{"place_key":"sajeongjeon","place":"사정전","area":"궁","clue":"근정전 바로 뒤, 임금께서 날마다 신하들과 나랏일을 의논하는 편전이오.","photo":"사정전에서 뒷날까지 꼭 남기고 싶은 것 하나를 찍으시오(현판이나 임금의 자리 같은 것).","diary":"그것을 주서답게 기록하고, 남기려고 고른 까닭을 덧붙이시오."},{"place_key":"geunjeongjeon","place":"근정전 품계석","area":"궁","clue":"근정전 앞 넓은 마당, 작은 돌비석이 두 줄로 늘어서 있소. 정일품부터 종구품까지 신하가 설 자리를 알려 주오.","photo":"정칠품 품계석 곁에 서서 근정전 쪽을 찍으시오.","diary":"정칠품 자리에서 근정전과 임금의 자리는 어떻게 보였소? 신하들의 자리를 이렇게 나눈 까닭은 무엇이겠소?"},{"place_key":"museum","place":"국립고궁박물관 · 조선의 국왕","area":"박물관","clue":"박물관 2층, 임금의 권위와 기록을 보여 주는 전시실이오.","photo":"임금의 권위를 보여 주는 물건(도장·책·깃발 같은 것) 하나를 찍으시오.","diary":"이 물건의 어떤 점에서 임금의 권위가 느껴지오? 주서답게 짧게 기록하시오."}],"ending":{"photo_mission":2,"body":{"then":["그대가 신하들의 자리를 적던 이 근정전 마당. 그 바로 앞, 흥례문이 있던 자리에 1916년부터 거대한 건물이 올라갔소. 흥례문을 헐어 낸 자리에 들어선 조선총독부 청사였소.","1926년 완공된 총독부 청사는 근정전 앞을 가로막았소. 임금이 신하를 만나던 마당이 식민 통치 기관의 뒤뜰이 되었소. 임금의 말을 적던 우리의 기록도 1910년 나라가 망하며 끊겼소."],"now":"1995년 광복 50주년에 총독부 청사 철거가 시작되어 이듬해 사라졌고, 2001년 흥례문이 다시 세워졌소. 우리가 쓴 『승정원일기』는 2001년 세계기록유산이 되었소.","prompt":"윤사겸에게 오늘의 근정전 마당을 기록해 보내시오.","old":{"at":1,"src":"then/df3c564b2dc2.jpg","cap":"1920년 무렵, 근정전 앞에 올라가는 조선총독부 청사","credit":"작자 미상 · 퍼블릭 도메인"}}}},{"id":"hwawon","sort":3,"name":"도화서 화원","person":"홍윤재","seal":"畵","intro":"임금의 병풍부터 잔치 기록화까지 궁궐의 그림을 맡은 화가.","career":"미술·디자인·웹툰","img":true,"letter":["나는 도화서 화원 홍윤재요.","궁궐에 필요한 그림이라면 무엇이든 그리오. 임금님 뒤를 지키는 병풍부터 잔치를 기록하는 그림, 전각을 꾸미는 무늬까지.","오늘은 궁궐 곳곳의 그림과 무늬를 살피러 나가오. 화원의 눈으로 함께 보아 주시오."],"missions":[{"place_key":"amisan","place":"아미산 굴뚝 (교태전 뒤뜰)","area":"궁","clue":"왕비의 집 교태전 뒤뜰 작은 동산, 붉은 벽돌 굴뚝에 무늬가 새겨져 있소.","photo":"굴뚝의 무늬 하나를 가까이 찍으시오.","diary":"그대가 찍은 무늬는 무엇을 그린 것이오? 연기 나가는 굴뚝에 이런 무늬를 넣은 까닭은?"},{"place_key":"geunjeongjeon","place":"근정전 일월오봉도","area":"궁","clue":"근정전 안, 임금의 자리 뒤에 해와 달, 다섯 봉우리를 그린 병풍이 있소. 근정전 문이 닫혀 있으면 바로 뒤 사정전 임금의 자리 뒤 병풍을 보시오.","photo":"근정전(문이 닫혀 있으면 사정전) 앞에서 안쪽 병풍이 보이게 찍으시오.","diary":"병풍에서 가장 눈에 띄는 색이나 모양 하나를 고르시오. 그것이 임금의 자리를 어떻게 돋보이게 하오?"},{"place_key":"museum","place":"국립고궁박물관 · 궁중서화","area":"박물관","clue":"박물관 지하층, 궁궐의 그림과 글씨가 모인 전시실이오.","photo":"그림 하나를 골라 화원의 눈으로 가장 공들인 부분을 찍으시오.","diary":"이 그림을 그린 화원이 가장 공들였을 부분은 어디이고, 왜 그렇게 생각하오?"}],"ending":{"photo_mission":1,"body":{"then":["그대가 찍은 굴뚝 바로 앞, 왕비의 집 교태전을 떠올려 보시오.","1917년 창덕궁에 큰불이 나 왕비의 침전 대조전이 타 버렸소. 일제는 1920년 경복궁의 교태전을 헐어 그 자재로 대조전을 다시 지었소. 임금의 침전 강녕전도 헐려 창덕궁 희정당이 되었소.","새로 지은 희정당 벽에는 화가 김규진이 금강산 그림을 그렸소. 경복궁의 나무로 지은 집에 새 시대의 그림이 걸린 것이오."],"now":"아미산 굴뚝은 헐리지 않고 살아남아 보물이 되었고, 교태전은 1995년 다시 지어졌소. 그대가 찍은 무늬는 그날 화원들이 보던 바로 그 무늬요.","prompt":"홍윤재에게 오늘 그대가 본 무늬를 그림처럼 설명해 주시오."}}},{"id":"gwansang","sort":4,"name":"관상감 관원","person":"최영휘","seal":"星","intro":"하늘을 살펴 달력과 시간을 만드는 관리. 조선 초 과학의 맥을 잇는다.","career":"천문·기상·데이터","img":true,"letter":["나는 관상감 관원 최영휘요.","우리 관상감은 하늘을 살펴 달력을 만들고 시간을 알리는 곳이오. 태조 임금 때 별 1,467개를 돌에 새긴 천상열차분야지도, 세종 임금 때 장영실이 만든 자격루와 해시계가 모두 우리 선배들의 솜씨요.","오백 년 전에 시작된 그 연구를 나는 오늘도 이어 가고 있소. 선배들이 남긴 흔적을 그대와 함께 찾아보고 싶소."],"missions":[{"place_key":"heumgyeonggak","place":"흠경각","area":"궁","clue":"왕비의 집 교태전 서쪽, 담장으로 둘러싸인 작은 전각이오. 세종 임금 때 장영실이 만든 자동 물시계 옥루를 두던 곳이라 하오.","photo":"흠경각 현판이 보이게 찍으시오.","diary":"선배 장영실의 옥루를 이어, 그대라면 무엇을 연구하겠소? 그 까닭은?"},{"place_key":"geunjeongjeon","place":"근정전 월대 돌짐승","area":"궁","clue":"근정전을 받치는 돌단(월대)의 난간과 모서리에 동물 조각들이 있소. 열두 띠 동물과 네 방위의 신이오. 열두 띠는 쥐(자시, 밤 11시~1시, 북쪽)에서 시작해 소·범·토끼(동쪽)·용·뱀·말(오시, 낮 11시~1시, 남쪽)·양·원숭이·닭(서쪽)·개·돼지 차례로 이어지고, 한 동물이 두 시간씩 맡소.","photo":"동물 조각 하나를 골라 찍으시오.","diary":"그대가 고른 동물은 무엇이고 월대의 어느 쪽에 있었소? 단서의 차례와 견주어 그 자리가 맞는지 확인하고, 그 동물이 맡은 시각을 적으시오."},{"place_key":"museum","place":"국립고궁박물관 · 과학문화 (천상열차분야지도)","area":"박물관","clue":"박물관 지하층 과학문화실이오. 별자리를 새긴 커다란 검은 돌판, 천상열차분야지도 각석을 찾으시오. 곁에 물시계와 해시계도 있소.","photo":"돌판에 새겨진 별자리가 보이게 찍으시오. 닳거나 흐릿해진 곳이 있는지도 살피시오.","diary":"먼저 돌판에서 알아본 것 하나(별자리 모양·글자·닳은 곳)를 적으시오. 선배들은 왜 별자리를 종이가 아닌 돌에 새겼을까?"}],"ending":{"photo_mission":3,"body":{"then":["그대가 찍은 이 돌은 조선을 세운 태조 때(1395) 하늘의 별 1,467개를 새긴 천상열차분야지도요. 임진왜란 뒤 사라졌다가 영조 때 다시 찾아, 우리 관상감이 귀하게 지켜 온 돌이오.","일제는 창경궁에 동물원과 식물원을 만들고 '창경원'이라 낮춰 불렀소. 이 돌은 그 명정전 뒤 처마 밑에 아무렇게나 놓였고, 1960년 무렵에도 소풍 온 사람들이 그 위에 신문지를 깔고 도시락을 펴 놓았다 하오."],"now":"1985년 국보가 되었고, 지금은 그대가 오늘 본 이 박물관에서 지켜지고 있소. 만 원짜리 지폐 뒷면에도 이 별자리가 새겨져 있고, 하늘을 살피던 관상감의 일은 오늘날 기상청과 천문연구원이 이어 가고 있소.","prompt":"최영휘에게, 오늘날 하늘과 우주를 연구하는 사람들 이야기를 전하시오.","old":{"at":1,"src":"then/3d5bfedcd83e.jpg","cap":"일제강점기 그림엽서 속 창경원 식물원","credit":"그림엽서 「경성 창경원 식물본관」 · 퍼블릭 도메인"}}}},{"id":"jimil","sort":5,"name":"지밀나인","person":"옥진","seal":"密","intro":"왕비 곁에서 하루를 함께하는 궁녀.","career":"비서·의전","img":true,"letter":["나는 중궁전 지밀나인 옥진이오.","열 살에 궁에 들어와 중전마마 곁을 지킨 지 어느덧 십 년이 되었소.","마마께서는 요즘 궁궐 가장 깊은 곳, 건청궁에 머무르시오. 마마 곁을 오가는 내 하루를 그대가 따라와 주시오."],"missions":[{"place_key":"gyotaejeon","place":"교태전","area":"궁","clue":"지붕 꼭대기에 용마루가 없는, 왕비의 집이오. 임금님 침전 강녕전 바로 뒤에 있소.","photo":"교태전 마당에서, 마마께서 부르시면 바로 달려갈 수 있는 나인의 자리 하나를 정해 찍으시오.","diary":"그 자리를 고른 까닭은 무엇이오? 그 자리에서 무엇이 보이고 무엇이 안 보이오?"},{"place_key":"geoncheonggung","place":"건청궁 곤녕합","area":"궁","clue":"궁궐 가장 북쪽, 향원정 연못 뒤에 단청 없이 소박한 집이 있소. 왕비가 머무는 곳의 이름은 곤녕합이오.","photo":"곤녕합 현판이나 건물을 찍으시오.","diary":"교태전에서 곤녕합까지 걸어 보았소? 마마를 모시는 나인에게 두 곳은 무엇이 다르오(거리·크기·단청·담장)? 하나를 골라, 그 차이가 마마의 하루를 어떻게 바꾸었을지 적으시오."},{"place_key":"museum","place":"국립고궁박물관 · 왕실생활","area":"박물관","clue":"박물관 2층, 왕실 사람들의 하루가 담긴 전시실이오.","photo":"왕비의 하루에 쓰였을 물건 하나를 찍으시오.","diary":"이 물건을 마마께 올리기 전에 지밀나인이 미리 살펴야 할 점 하나는 무엇이오? 물건의 모양이나 재료를 보고 까닭을 적으시오."}],"ending":{"photo_mission":2,"body":{"then":["1895년 10월 8일 새벽, 일본 공사 미우라가 보낸 무리가 그대가 찍은 이 곤녕합에 들이닥쳤소.","중전마마께서 목숨을 잃으셨고, 마마 곁을 지키던 궁녀들도 화를 입었소. 이 일을 을미사변이라 부르오.","1909년 건청궁은 통째로 헐렸소."],"now":"2007년 건청궁은 옛 모습대로 다시 지어졌소. 그대가 오늘 선 곳은 그날의 그 자리요.","prompt":"옥진에게, 오늘 그대가 곤녕합 앞에서 본 것과 든 생각을 전하시오."}}},{"id":"chimbang","sort":6,"name":"침방 나인","person":"순덕","seal":"針","intro":"대비마마의 옷을 짓고 수를 놓는 궁녀.","career":"패션·섬유공예","img":true,"letter":["나는 침방 나인 순덕이오.","자경전에 계신 대비마마의 옷을 짓고, 바늘 한 땀 한 땀에 마마의 강녕을 비는 것이 내 일이오.","오늘은 마마의 거처에 새겨진 무늬를 보고 새 옷에 놓을 수를 구상하려 하오."],"missions":[{"place_key":"jagyeongjeon","place":"자경전 꽃담","area":"궁","clue":"교태전 동쪽, 대비마마의 거처 자경전 서쪽 담에 꽃과 글자 무늬가 새겨져 있소.","photo":"꽃담 무늬 하나를 가까이 찍으시오.","diary":"이 무늬를 새 옷에 수놓는다면 어디에, 왜 놓겠소?"},{"place_key":"jagyeongjeon","place":"자경전 십장생 굴뚝","area":"궁","clue":"자경전 뒤뜰 담에 붙은 굴뚝이오. 해·산·물·소나무·사슴처럼 오래 사는 것들이 새겨져 있소.","photo":"십장생 가운데 하나를 찾아 찍으시오.","diary":"십장생 가운데 그대가 찍은 것은 무엇이오? 대비마마께 그 무늬를 골라 드린 까닭을 적으시오."},{"place_key":"museum","place":"국립고궁박물관 · 왕실생활","area":"박물관","clue":"박물관 2층, 왕실의 옷과 장신구가 있는 전시실이오.","photo":"옷이나 장신구 하나를 골라 무늬가 보이게 찍으시오.","diary":"이 옷을 지을 때 가장 조심했을 부분은 어디이고, 왜 그렇게 생각하오?"}],"ending":{"photo_mission":1,"body":{"then":["그대가 찍은 이 꽃담의 주인, 자경전을 다시 보시오.","일제강점기에 경복궁의 전각 대부분이 헐리고 팔려 나갔소. 고종 때 330여 동이던 전각 가운데, 복원이 시작되기 전 남아 있던 것은 서른여섯 동뿐이었소.","그 와중에도 자경전은 1888년 다시 지은 모습 그대로 살아남았소."],"now":"자경전과 십장생 굴뚝은 지금 보물이오. 그대가 찍은 꽃담은 순덕이 보던 그 꽃담 그대로요.","prompt":"순덕에게, 그대가 고른 무늬로 어떤 소원을 수놓고 싶은지 전하시오."}}},{"id":"uinyeo","sort":7,"name":"내의원 의녀","person":"연희","seal":"醫","intro":"임금과 왕실 어른들의 몸을 살피고 약을 달이는 의녀.","career":"의료·간호·약학","img":true,"letter":["나는 내의원 의녀 연희요.","임금님과 왕실 어른들의 몸을 살피고, 약을 달이고, 침 놓는 법을 배우고 있소.","요즘은 바다 건너 미국에서 온 여인 엘러스가 서양 의술로 중전마마를 진찰한다 하여 궁궐이 술렁이오. 오늘 내 하루를 그대가 함께 해 주시오."],"missions":[{"place_key":"gangnyeongjeon","place":"강녕전","area":"궁","clue":"사정전 바로 뒤, 지붕에 용마루가 없는 임금님의 침전이오. 아침마다 내의원 사람들이 문안을 드리는 곳이오.","photo":"강녕전을 둘러보고, 임금님이 편히 쉬시도록 의녀로서 살피고 싶은 곳(방·마루·문 같은 곳)을 찍으시오.","diary":"그곳을 고른 까닭과, 의녀로서 무엇을 살피거나 챙기겠는지 적으시오."},{"place_key":"jagyeongjeon","place":"자경전","area":"궁","clue":"교태전 동쪽, 대비마마의 거처요. 방을 데우는 굴뚝이 뒤뜰 담에 붙어 있소.","photo":"자경전에서 대비마마의 몸을 따뜻하고 편하게 하는 곳(굴뚝이나 방 같은 것)을 찾아 찍으시오.","diary":"온돌로 방을 데우는 이 집에서, 대비마마의 건강을 위해 의녀로서 좋은 점 하나와 살필 점 하나는 무엇이오?"},{"place_key":"museum","place":"국립고궁박물관 · 대한제국","area":"박물관","clue":"박물관 1층, 황실이 서양식으로 살기 시작하던 시대의 전시실이오.","photo":"황실이 쓰던 서양식 생활용품(그릇·가구·등 같은 것) 하나를 찍으시오.","diary":"이 물건이 궁궐에 들어온 것을 보며, 의녀로서 반가운 점 하나와 걱정되는 점 하나를 적으시오. 물건의 어떤 점을 보고 그렇게 생각했소?"}],"ending":{"photo_mission":1,"body":{"then":["그대가 찍은 강녕전, 내가 아침마다 문안을 드리던 임금님의 침전이오.","1895년 을미사변 뒤 임금님은 궁궐 안에서도 마음을 놓지 못하셨소. 1896년 2월 11일 새벽, 임금님과 세자는 궁녀의 가마를 타고 경복궁을 빠져나가 러시아 공사관으로 가셨소. 아관파천이오.","임금님은 다시는 경복궁에 돌아와 사시지 않았소. 주인 잃은 강녕전은 1920년 헐려 창덕궁 희정당을 짓는 데 쓰였소."],"now":"강녕전은 1995년 다시 지어졌소. 엘러스가 일하던 제중원의 서양 의술은 오늘날의 병원으로 이어졌고, 이제는 수많은 여성이 의사와 간호사로 일하오.","prompt":"연희에게, 오늘날 사람의 몸과 마음을 돌보는 일에 대해 알려 주시오."}}},{"id":"sukso","sort":8,"name":"소주방 숙수","person":"박만복","seal":"膳","intro":"임금의 수라와 잔치 음식을 만드는 궁궐 요리사.","career":"조리·식품·영양","img":true,"letter":["나는 대전 소주방 숙수 박만복이오.","임금님 수라와 궁궐 잔치 음식을 만드오. 궁궐 부엌은 새벽부터 불이 꺼지지 않소.","오늘 수라를 지어 올리는 길을 그대가 따라와 주시오."],"missions":[{"place_key":"sojubang","place":"소주방","area":"궁","clue":"강녕전 동쪽, 세자의 거처 동궁과의 사이에 큰 부엌 마을이 있소. 내소주방·외소주방·생물방으로 나뉘오.","photo":"소주방 현판이나 부엌 안쪽을 찍으시오.","diary":"소주방은 내소주방·외소주방·생물방으로 나뉘오. 부엌을 이렇게 나눈 까닭을 숙수로서 짐작해 보시오."},{"place_key":"gangnyeongjeon","place":"강녕전","area":"궁","clue":"수라상을 들고 가는 곳, 임금님의 침전이오. 사정전 바로 뒤에 있소.","photo":"수라상이 들어갔을 문이나 마루를 찍으시오.","diary":"소주방에서 강녕전까지 오는 길을 떠올려 보시오. 수라상을 들고 갈 때 가장 조심했을 곳은 어디이고, 왜 그렇소?"},{"place_key":"museum","place":"국립고궁박물관 · 왕실의례","area":"박물관","clue":"박물관 지하층, 나라의 큰 의례와 잔치에 쓰던 물건들이 모인 곳이오.","photo":"음식을 차려 올리던 그릇이나, 잔칫상·제사상이 그려진 그림 하나를 찍으시오.","diary":"그릇의 모양이나 크기를 보고, 어떤 음식을 올렸을지 까닭과 함께 짐작하시오."}],"ending":{"photo_mission":1,"body":{"then":["그대가 찍은 이 소주방을 다시 보시오.","1915년 일제는 경복궁에서 조선물산공진회라는 박람회를 열었소. 식민 통치의 성과를 자랑하려는 행사였지. 그때 궁궐 전각 수천 칸이 헐렸고, 궁궐 부엌 소주방도 함께 사라졌소."],"now":"2015년, 100년 만에 소주방이 다시 지어졌소. 그대가 찍은 부엌은 발굴한 옛터 위에 되살린 것이오.","prompt":"박만복에게, 다시 불을 지핀 소주방 소식을 전하시오.","old":{"at":1,"src":"then/1a9b1e547103.jpg","cap":"1915년 공진회 때 경복궁 안에 꾸민 정원과 전시관","credit":"프랑스국립도서관 소장 1915년 공진회 사진첩 · 퍼블릭 도메인"}}}},{"id":"moksu","sort":9,"name":"중건 공사 목수","person":"한석","seal":"木","intro":"불탄 지 270년 만에 경복궁을 다시 세운 목수.","career":"건축·문화재 수리","img":true,"letter":["나는 경복궁 중건 공사에 참여한 목수 한석이오.","임진년 왜란 때 불탄 뒤 270년 넘게 빈터였던 이 궁궐을 우리가 다시 세웠소. 공사비 때문에 백성의 원성도 컸지만, 우리 목수들은 나무 하나하나에 혼을 담았소.","내가 지은 건물들을 그대에게 보여 주고 싶소."],"missions":[{"place_key":"geunjeongjeon","place":"근정전 잡상","area":"궁","clue":"근정전 지붕 끝 비탈진 마루에 작은 흙 인형들이 줄지어 앉아 있소.","photo":"지붕 위 잡상 가운데 하나를 골라 크게 찍으시오(화면을 키워도 되오).","diary":"그대가 고른 잡상은 어떤 모습이오? 목수라면 왜 이런 모습으로 만들었다고 보오?"},{"place_key":"gyeonghoeru","place":"경회루 (바깥에서)","area":"궁","clue":"근정전 서쪽, 연못 위에 돌기둥 마흔여덟 개가 받친 큰 누각이오.","photo":"연못과 누각이 함께 나오게 찍으시오.","diary":"돌기둥과 연못을 살펴보시오. 이 큰 누각을 연못 위에 세울 때 가장 어려웠을 일은 무엇이고, 왜 그렇게 보오?"},{"place_key":"museum","place":"국립고궁박물관 (전시실 자유)","area":"박물관","clue":"박물관 어느 전시실이든 좋소. 궁궐 건축과 관련된 유물(현판·기와·장식 등)을 찾으시오.","photo":"궁궐 건축과 관련된 유물 하나를 찍으시오.","diary":"목수의 눈으로 이 유물에서 가장 솜씨 좋은 곳 하나를 골라, 까닭과 함께 평가하시오."}],"ending":{"photo_mission":1,"body":{"then":["그대가 찍은 근정전 지붕의 잡상, 그리고 경회루. 이 건물들은 살아남았소.","그러나 함께 지은 전각들은 달랐소. 1915년 박람회 때 궁궐 전각 수천 칸이 헐려 팔려 나갔고, 1917년 창덕궁에 불이 나자 교태전과 강녕전까지 헐려 그 재목으로 쓰였소.","고종 때 330여 동이던 전각 가운데, 복원이 시작되기 전 남아 있던 것은 서른여섯 동뿐이었소."],"now":"1990년부터 이어진 복원으로 사라진 전각들이 하나둘 돌아오고 있소. 지금도 목수들이 옛 방식대로 나무를 다듬어 궁궐을 다시 짓고 있소.","prompt":"한석에게, 오늘 본 경복궁에서 가장 오래 기억할 곳과 그 까닭을 전하시오.","old":{"at":1,"src":"then/2019b0bbca01.jpg","cap":"1915년 공진회 때 경복궁 안에 세운 전시관(제1호관)","credit":"프랑스국립도서관 소장 1915년 공진회 사진첩 · 퍼블릭 도메인"}}}},{"id":"jeongi","sort":10,"name":"전등 기술 조수","person":"정순길","seal":"電","intro":"건청궁에 조선 최초의 전등을 밝히는 일을 돕는 조수.","career":"전기·전자 공학","img":true,"letter":["나는 건청궁 전등 일을 돕는 조수 정순길이오.","바다 건너 미국 에디슨 회사에서 온 기술자들과 함께, 향원정 연못물을 끌어 기계를 돌려 불을 밝히오. 궁궐 사람들은 물에서 나온 불이라 하여 '물불'이라 부르오.","처음 불이 켜지던 밤을 그대에게 보여 주고 싶소."],"missions":[{"place_key":"hyangwonjeong","place":"향원정 연못 · 전기 발상지 표석","area":"궁","clue":"궁궐 북쪽, 연못 가운데 섬에 정자가 있소. 연못가 어딘가에 전기가 처음 켜진 곳을 알리는 표석이 있소.","photo":"전기 발상지 표석을 찾아 찍으시오.","diary":"표석을 읽고 연못을 둘러보시오. 연못물로 불을 밝히려면 어떤 장치가 필요했겠소? 조수로서 짐작해 보시오."},{"place_key":"geoncheonggung","place":"건청궁","area":"궁","clue":"향원정 연못 바로 뒤, 임금과 왕비가 머무는 단청 없는 집이오.","photo":"건청궁에서 전등을 달고 싶은 자리가 보이게 찍으시오.","diary":"그 자리에 전등을 달려는 까닭은 무엇이오? 불을 켜면 무엇이 달라지겠소?"},{"place_key":"museum","place":"국립고궁박물관 · 지하 2층 (어차)","area":"박물관","clue":"박물관 지하 2층, 황제와 황후가 타던 자동차(어차)가 있소.","photo":"어차에서 새로운 기술이 드러나는 부분(전조등·운전대 같은 곳)을 골라 찍으시오.","diary":"가마를 타던 때와 견주어, 자동차가 들어와 편해지는 점 하나는 무엇이오? 또 자동차가 다니려면 새로 바뀌어야 할 것(길·신호·규칙 같은 것) 하나는 무엇이겠소?"}],"ending":{"photo_mission":2,"body":{"then":["그대가 찍은 건청궁, 조선에 처음 전등이 켜진 곳이오.","1895년 이곳에서 을미사변이 일어났고, 이듬해 임금님은 궁을 떠나셨소. 주인 잃은 건청궁은 1909년 통째로 헐렸소.","1939년 그 자리에는 조선총독부 미술관이 들어섰소."],"now":"2007년 건청궁은 옛 모습대로 다시 지어졌소. 연못가의 표석이 그날의 불빛을 기억하고 있소.","prompt":"정순길에게 지금 우리가 쓰는 전기 이야기를 들려주시오."}}},{"id":"tongyeok","sort":11,"name":"연회 통역관","person":"변수진","seal":"譯","intro":"외국 손님 앞에서 임금의 말을 옮기는 역관.","career":"언어·통번역·외교","img":true,"letter":["나는 사역원 역관 변수진이오.","청나라 말과 일본 말을 익혔고, 요즘은 영어까지 배우고 있소. 경회루에서 외국 손님을 맞는 연회가 열리면 임금님 말씀을 옮기는 것이 내 일이오.","나라 밖이 시끄러운 때, 말 한마디의 무게를 그대도 느껴 보시오."],"missions":[{"place_key":"gyeonghoeru","place":"경회루 (바깥에서)","area":"궁","clue":"근정전 서쪽, 연못 위의 큰 누각이오. 나라의 손님을 맞는 연회가 열리오.","photo":"연회가 열리는 누각을 찍으시오.","diary":"경회루에서 본 것 하나를 들어, 외국 손님에게 조선을 한 문장으로 소개하시오. 그것을 고른 까닭도 적으시오."},{"place_key":"sujeongjeon","place":"수정전","area":"궁","clue":"경회루 남쪽, 넓은 돌단을 앞에 둔 전각이오. 옛 집현전 자리라 하오.","photo":"수정전 건물이나 현판을 찍으시오.","diary":"나랏일을 의논하는 자리에서 말을 잘못 옮기면 어떤 일이 생기겠소? 통역관으로서 가장 조심할 점을 적으시오."},{"place_key":"museum","place":"국립고궁박물관 · 대한제국","area":"박물관","clue":"박물관 1층, 서양 사람들이 조선을 그려 자기 나라에 소개한 잡지와 책이 있는 곳이오(서양인이 본 대한제국 풍경).","photo":"서양 잡지나 책이 조선을 그린 장면 하나를 찍으시오.","diary":"서양 사람 눈에 조선은 이렇게 보였구려. 통역관으로서 이 소개에서 바로잡거나 덧붙이고 싶은 것은 무엇이오? 그림에서 본 것을 들어 적으시오."}],"ending":{"photo_mission":2,"body":{"then":["그대가 찍은 수정전을 다시 보시오.","1894년 7월 23일 새벽, 일본군이 경복궁에 쳐들어와 궁궐을 점령했소. 청과 전쟁을 벌이기 직전이었소.","그 뒤 이 수정전에 군국기무처가 설치되어 갑오개혁을 밀어붙였소. 개혁의 자리였지만, 일본군의 총칼 아래에서 시작된 개혁이었소."],"now":"수정전은 고종 때 지은 모습 그대로 지금까지 남았소. 그대가 찍은 그 건물에서 그 일이 있었소.","prompt":"변수진에게, 말 한마디의 무게에 대해 한마디를 남기시오."}}},{"id":"sigangwon","sort":12,"name":"세자시강원 관원","person":"이도명","seal":"講","intro":"세자(훗날 순종)에게 글을 가르치는 세자의 스승.","career":"교육·교사·상담","img":true,"letter":["나는 세자시강원의 관원 이도명이오.","동궁에 계신 세자 저하께 아침·낮·저녁으로 글을 가르치오. 장차 임금이 되실 분의 스승이라는 무게가 늘 어깨를 누르오.","오늘 저하의 하루를 그대가 함께 살펴 주시오."],"missions":[{"place_key":"bihyeongak","place":"동궁 비현각","area":"궁","clue":"사정전 동쪽, 세자가 사는 동궁이오. 그 가운데 세자가 글을 읽고 공부하던 집이 비현각이오.","photo":"비현각 현판이나 건물을 찍으시오.","diary":"지금은 나라 밖이 시끄러운 때요. 장차 임금이 되실 저하께 꼭 가르칠 것 하나와 그 까닭은? 비현각에서 본 것 하나를 들어도 좋소."},{"place_key":"donggung","place":"동궁 자선당","area":"궁","clue":"비현각 바로 옆, 세자와 세자빈이 머무는 집이오.","photo":"자선당 건물을 찍으시오.","diary":"공부를 힘들어하는 세자 저하께 스승으로서 어떤 말을 해 드리겠소?"},{"place_key":"museum","place":"국립고궁박물관 · 조선의 국왕 (국왕의 교육)","area":"박물관","clue":"박물관 2층 조선의 국왕 전시실에서 \"국왕의 교육\" 자리를 찾으시오. 세자가 공부하던 책들이 있소.","photo":"세자가 공부하던 책이나 교육에 쓰인 물건 하나를 찍으시오.","diary":"이 책으로 공부할 세자께 꼭 가르쳐야 할 것은 무엇이오? 책이나 물건의 어떤 점을 보고 그렇게 생각했소?"}],"ending":{"photo_mission":2,"body":{"then":["그대가 찍은 자선당, 세자 저하께서 머무시던 집이오.","1914년, 일본의 부호 오쿠라 기하치로가 이 자선당을 통째로 뜯어 도쿄의 자기 집으로 실어 갔소. 이름도 조선관이라 바꾸어 개인 미술관으로 썼소.","1923년 관동대지진 때 건물은 불타 버리고, 기단과 주춧돌만 남았소."],"now":"1995년 그 돌들이 돌아와 건청궁 동쪽 녹산에 놓였소. 그대가 찍은 자선당과 비현각은 1999년 원래 자리에 다시 지은 것이오.","prompt":"이도명에게, 오늘날의 선생님과 학생 이야기를 들려주시오."}}},{"id":"sajin","sort":13,"name":"궁궐 사진 견습생","person":"노경환","seal":"寫","intro":"서양에서 들어온 사진기로 궁궐을 처음 담아 보는 견습생.","career":"사진·영상·미디어","img":true,"letter":["나는 사진 견습생 노경환이오.","서양에서 들어온 사진이라는 신기한 기계로 궁궐을 담아 보라는 명을 받았소. 사람들은 사진기가 혼을 빼 간다며 무서워하지만, 나는 이 기계가 오늘을 영원히 남길 것이라 믿소.","그대의 눈이 곧 나의 사진기요."],"missions":[{"place_key":"hyangwonjeong","place":"향원정","area":"궁","clue":"궁궐 북쪽, 연못 가운데 섬의 육각 정자와 나무다리요.","photo":"내가 생각하는 가장 아름다운 구도로 찍으시오.","diary":"이 구도를 고른 까닭을 사진사로서 설명하시오."},{"place_key":"geunjeongjeon","place":"근정전","area":"궁","clue":"궁궐 한가운데, 두 겹 돌단 위의 가장 큰 전각이오.","photo":"근정전을 그대만의 구도로 찍으시오.","diary":"이 사진에 일부러 담은 것 하나는 무엇이오? 백 년 뒤 사람이 이 사진에서 그것을 보고 알게 될 사실은?"},{"place_key":"museum","place":"국립고궁박물관 · 지하 2층 (화성능행도 병풍)","area":"박물관","clue":"박물관 지하 2층, 정조 임금의 화성 행차를 그린 화성능행도 병풍이 있소.","photo":"병풍 그림 가운데 한 장면을 골라, 사람이나 건물이 사진처럼 정밀하게 그려진 부분을 찍으시오.","diary":"이 장면을 사진기로 찍었다면 그림과 무엇이 달랐겠소?"}],"ending":{"photo_mission":2,"body":{"then":["그대가 찍은 근정전을 다시 보시오.","1915년 일제는 경복궁에서 조선물산공진회라는 박람회를 열었소. 주변 전각을 헐어 낸 자리에 전시관이 들어섰고, 궁궐은 구경거리가 되었소.","근정전 앞에 일장기가 엇갈려 걸린 그날의 사진이 지금도 남아 있소."],"now":"근정전은 고종 때 모습 그대로 살아남아 국보가 되었소. 그대가 오늘 찍은 사진은 백 년 뒤 무엇을 말해 줄까?","prompt":"노경환에게, 그대가 찍은 사진을 한 문장으로 설명해 보내시오.","old":{"at":1,"src":"then/9f62af8c5d50.jpg","cap":"1915년 공진회 때 식장이 된 근정전","credit":"프랑스국립도서관 소장 1915년 공진회 사진첩 · 퍼블릭 도메인"}}}},{"id":"akgong","sort":14,"name":"장악원 악공","person":"함덕보","seal":"樂","intro":"조회와 잔치, 제사 때 궁중 음악을 연주하는 악공.","career":"음악·공연예술","img":true,"letter":["나는 장악원 악공 함덕보요.","큰 조회와 잔치, 제사 때 음악을 연주하오. 근정전 마당에서 편종이 울리면 온 궁궐이 고요해지오.","오늘 궁궐에 울릴 소리를 그대와 함께 찾고 싶소."],"missions":[{"place_key":"geunjeongjeon","place":"근정전 마당","area":"궁","clue":"근정전 앞, 박석이 깔린 넓은 마당이오. 조회 때 악공들이 자리를 잡소. 조회 날에는 편종·편경이 울리는 느리고 엄숙한 음악을 연주하오.","photo":"마당에서 잠시 귀를 기울인 뒤, 악공들이 섰을 법한 자리에서 근정전을 찍으시오.","diary":"근정전 마당에서 어떤 소리가 들렸소? 조회 날 이 마당에 울렸을 음악과 견주어 적으시오."},{"place_key":"gyeonghoeru","place":"경회루 (바깥에서)","area":"궁","clue":"근정전 서쪽, 연못 위의 큰 누각이오. 잔치 음악이 물 위로 퍼지오.","photo":"연못과 누각을 찍으시오.","diary":"물 위의 누각이라는 점을 생각하면, 이곳 잔치에는 어떤 분위기의 음악이 어울리겠소? 그 까닭은?"},{"place_key":"museum","place":"국립고궁박물관 · 왕실의례","area":"박물관","clue":"박물관 지하층, 나라의 큰 의례에 쓰던 물건들이 있소. 악기를 찾으시오.","photo":"궁중 악기 하나를 찍으시오.","diary":"악기의 재료와 생김새를 보고, 어떤 소리가 날지 짐작해 설명하시오."}],"ending":{"photo_mission":1,"body":{"then":["그대가 서 있던 이 근정전 마당에 다시 귀를 기울여 보시오.","1910년 나라가 망한 뒤 장악원은 '이왕직 아악부'라는 작은 부서로 줄었고, 악공의 수도 크게 줄었소.","그래도 남은 이들은 궁중 음악을 이어 가며 제자를 길렀소."],"now":"해방 뒤 1951년, 그 맥은 국립국악원으로 이어졌소. 근정전 마당에 울리던 음악은 지금도 연주되고, 종묘제례악은 세계무형유산이 되었소.","prompt":"함덕보에게, 그대가 오늘 들은 궁궐의 소리를 전하시오."}}}]$gpseed$::jsonb) x;

insert into public.gp_roles(id, sort, enabled, name, person, seal, intro, career, letter, img)
select x->>'id', (x->>'sort')::smallint, true, x->>'name', x->>'person', x->>'seal', x->>'intro', x->>'career', x->'letter', (x->>'img')::boolean
from gp_seed;

insert into public.gp_missions(role_id, n, place_key, place, area, clue, photo, diary)
select x->>'id', m.n::smallint, m.v->>'place_key', m.v->>'place', m.v->>'area', m.v->>'clue', m.v->>'photo', m.v->>'diary'
from gp_seed, jsonb_array_elements(x->'missions') with ordinality m(v, n);

insert into public.gp_endings(role_id, photo_mission, body)
select x->>'id', (x->'ending'->>'photo_mission')::smallint, x->'ending'->'body'
from gp_seed where jsonb_typeof(x->'ending') = 'object';

drop table gp_seed;

-- ---------------------------------------------------------------- 끝
-- 아래 결과 칸의 설치 코드를 적어 두고, 앱 첫 화면 [첫 설정]에서 관리자 계정을 만드시오.
select setup_code as "설치 코드(관리자 만들 때 한 번)", join_code as "학생 입장 코드(관리자 화면에서 바꿀 수 있음)" from public.gp_settings;
