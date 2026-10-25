-- 설치 코드 다시 만들기: 설치 뒤 24시간 안에 관리자를 만들지 못했을 때 SQL Editor에서 실행한다.
-- 관리자가 이미 있으면 아무것도 바꾸지 않는다. 결과 칸의 새 코드로 앱 첫 화면에서 관리자를 만든다(24시간 유효).
update public.gp_settings
set setup_code = upper(substr(md5(gen_random_uuid()::text), 1, 12)), setup_until = now() + interval '24 hours'
where id and not exists (select 1 from public.gp_staff where kind = 'admin');
select case when exists (select 1 from public.gp_staff where kind = 'admin') then '관리자가 이미 있습니다. 앱에서 로그인하세요.'
            else setup_code end as "새 설치 코드" from public.gp_settings;
