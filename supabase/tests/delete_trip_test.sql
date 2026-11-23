begin;
select plan(11);

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000d1');
insert into couples (id, user_a_id, user_b_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001'
  where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
update users set active_couple_id = '10000000-0000-0000-0000-000000000002'
  where id in ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1');

-- 수동 여행 M, 자동 여행 X(A와 B의 사진, 방명록), 다른 커플의 여행 Z
insert into trips (id, couple_id, title, started_on, ended_on, status, source) values
  ('30000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', '수동', '2026-10-01', '2026-10-01', 'confirmed', 'manual'),
  ('30000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001', '자동', '2026-10-03', '2026-10-04', 'confirmed', 'auto'),
  ('30000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000002', '남의 것', '2026-10-03', '2026-10-03', 'confirmed', 'manual');
insert into trip_regions (trip_id, couple_id, region_id) values
  ('30000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', '32060'),
  ('30000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001', '32060'),
  ('30000000-0000-0000-0000-00000000000c', '10000000-0000-0000-0000-000000000002', '32060');
insert into photos (id, trip_id, couple_id, object_key, width, height, byte_size, uploaded_by) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-00000000000a/m.heic', 1, 1, 1, '00000000-0000-0000-0000-0000000000a1'),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-00000000000b/a.heic', 1, 1, 1, '00000000-0000-0000-0000-0000000000a1'),
  ('40000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-00000000000b/b.heic', 1, 1, 1, '00000000-0000-0000-0000-0000000000b1');
update trips set cover_photo_id = '40000000-0000-0000-0000-000000000002'
  where id = '30000000-0000-0000-0000-00000000000b';
insert into guestbook_entries (trip_id, couple_id, author_id, content) values
  ('30000000-0000-0000-0000-00000000000b', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', '또 가자');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);

-- B가 A의 사진이 든 수동 여행을 지운다
select lives_ok($$ select delete_trip('30000000-0000-0000-0000-00000000000a') $$, 'B가 수동 여행을 지운다');
reset role;
select is((select count(*)::int from trips where id = '30000000-0000-0000-0000-00000000000a'), 0, '수동 여행은 행이 사라진다');
select is((select count(*)::int from photos where id = '40000000-0000-0000-0000-000000000001'), 0, '상대가 올린 사진도 지워진다');

-- 자동 여행은 버린 여행으로 남아 같은 기간이 후보로 다시 뜨지 않는다
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select lives_ok($$ select delete_trip('30000000-0000-0000-0000-00000000000b') $$, 'B가 자동 여행을 지운다');
reset role;
select is((select status from trips where id = '30000000-0000-0000-0000-00000000000b'), 'dismissed', '자동 여행은 버린 여행이 된다');
select is((select cover_photo_id from trips where id = '30000000-0000-0000-0000-00000000000b'), null, '표지가 비워진다');
select is((select count(*)::int from photos where trip_id = '30000000-0000-0000-0000-00000000000b'), 0, '두 사람 사진이 모두 지워진다');
select is((select count(*)::int from trip_regions where trip_id = '30000000-0000-0000-0000-00000000000b'), 0, '조각이 빠진다');
select is((select count(*)::int from guestbook_entries where trip_id = '30000000-0000-0000-0000-00000000000b'), 0, '방명록이 지워진다');

-- 다른 커플의 여행은 지우지 못한다
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select throws_ok($$ select delete_trip('30000000-0000-0000-0000-00000000000c') $$, 'P0001', 'trip_not_found', '남의 여행은 지울 수 없다');

-- 연결을 끊은 뒤(지난 기록)에는 지우지 못한다
reset role;
update users set active_couple_id = null where id in ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1');
update couples set status = 'archived', archived_at = now() where id = '10000000-0000-0000-0000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select throws_ok($$ select delete_trip('30000000-0000-0000-0000-00000000000c') $$, 'P0001', 'trip_not_found', '지난 기록의 여행은 지울 수 없다');

select * from finish();
rollback;
