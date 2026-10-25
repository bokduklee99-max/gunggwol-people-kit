-- 궁궐 사람들 키트 지우기: gp_ 표·함수·사진 보관함 정책을 모두 지운다. 되돌릴 수 없다.
-- 먼저 Supabase 대시보드 → Storage → gp-photos 버킷의 사진을 모두 지우거나(앱 관리자 화면 [기록 지우기]),
-- 버킷째 지운 뒤 이 SQL을 실행한다. 사진이 남아 있으면 마지막 줄(버킷 지우기)에서 멈춘다.

drop policy if exists gp_photos_insert on storage.objects;
drop policy if exists gp_photos_select on storage.objects;
drop policy if exists gp_photos_delete on storage.objects;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like 'gp\_%' loop
    execute format('drop function if exists %s cascade', f.sig);
  end loop;
end $$;

drop table if exists public.gp_login_fail, public.gp_group_members, public.gp_groups, public.gp_final, public.gp_entries,
  public.gp_bind, public.gp_students, public.gp_endings, public.gp_missions, public.gp_roles, public.gp_staff, public.gp_settings cascade;

delete from storage.buckets where id = 'gp-photos';
