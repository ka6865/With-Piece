begin;
select plan(2);
-- tablename은 name 타입(C 콜레이션)이라 문자열과 비교하려면 콜레이션을 맞춘다
select is(
  array(select tablename::text collate "default" from pg_publication_tables
        where pubname = 'supabase_realtime' and schemaname = 'public' order by 1),
  array['couple_region_overrides', 'couples', 'photos', 'trip_regions', 'trips'],
  '상대 변경을 반영할 테이블만 Realtime으로 발행한다');
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname in ('photos', 'trip_regions', 'couple_region_overrides') and c.relreplident = 'f'),
 3, '삭제 이벤트도 커플 필터에 필요한 이전 행을 갖는다');
select * from finish();
rollback;
