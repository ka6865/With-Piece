begin;
select plan(2);
-- 파일 삭제 정책은 SQL 직접 삭제가 막혀 있어 Dart 통합 테스트(Storage API)로 확인한다

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1');
insert into couples (id, user_a_id, user_b_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001';
insert into trips (id, couple_id, title, started_on, ended_on, status, source) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '속초', '2026-10-03', '2026-10-03', 'confirmed', 'manual');
insert into photos (id, trip_id, couple_id, object_key, width, height, byte_size, uploaded_by) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/a.heic', 1, 1, 1,
   '00000000-0000-0000-0000-0000000000a1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
delete from photos where id = '40000000-0000-0000-0000-000000000001';
reset role;
select is((select count(*)::int from photos where id = '40000000-0000-0000-0000-000000000001'), 1, '상대는 내 사진 행을 지우지 못한다');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
delete from photos where id = '40000000-0000-0000-0000-000000000001';
reset role;
select is((select count(*)::int from photos where id = '40000000-0000-0000-0000-000000000001'), 0, '올린 사람은 사진 행을 지운다');

select * from finish();
rollback;
