begin;
select plan(12);

-- a·b 커플, c·d 다른 커플. 속초(32060) 사진 하나, 경주(37020) 사진 하나, 다른 커플 속초 사진 하나
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
insert into trips (id, couple_id, title, started_on, ended_on, status, source) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '속초', '2026-10-03', '2026-10-03', 'confirmed', 'manual'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '속초', '2026-10-03', '2026-10-03', 'confirmed', 'manual');
insert into photos (id, trip_id, couple_id, region_id, object_key, width, height, byte_size, uploaded_by) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '32060',
   '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/a.heic', 1, 1, 1, '00000000-0000-0000-0000-0000000000a1'),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '37020',
   '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/b.heic', 1, 1, 1, '00000000-0000-0000-0000-0000000000a1'),
  ('40000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '32060',
   '10000000-0000-0000-0000-000000000002/30000000-0000-0000-0000-000000000002/c.heic', 1, 1, 1, '00000000-0000-0000-0000-0000000000c1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select lives_ok($$ insert into region_covers (couple_id, region_id, photo_id, scale, center_x, center_y)
  values ('10000000-0000-0000-0000-000000000001', '32060', '40000000-0000-0000-0000-000000000001', 1.5, 0.4, 0.6) $$,
  '내 커플 사진으로 그 조각의 대표 사진을 정한다');
select is((select updated_by from region_covers), '00000000-0000-0000-0000-0000000000a1'::uuid, '바꾼 사람은 서버가 정한다');
select throws_ok($$ insert into region_covers (couple_id, region_id, photo_id, scale, center_x, center_y)
  values ('10000000-0000-0000-0000-000000000001', '32400', '40000000-0000-0000-0000-000000000002', 1, 0.5, 0.5) $$,
  '42501', null, '그 조각이 들어 있지 않은 여행의 다른 조각 사진은 대표 사진이 되지 못한다');
-- 여행에 가평(31370)이 들어 있으면 그 여행의 다른 조각(경주) 사진도 고를 수 있다
reset role;
insert into trip_regions (trip_id, couple_id, region_id) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '31370');
set local role authenticated;
select lives_ok($$ insert into region_covers (couple_id, region_id, photo_id, scale, center_x, center_y)
  values ('10000000-0000-0000-0000-000000000001', '31370', '40000000-0000-0000-0000-000000000002', 1, 0.5, 0.5) $$,
  '같은 여행의 다른 조각 사진은 대표 사진이 된다');
select is((select count(*)::int from region_covers where region_id = '31370'), 1, '같은 여행 사진으로 정한 행이 있다');
select throws_ok($$ update region_covers set photo_id = '40000000-0000-0000-0000-000000000003'
  where region_id = '32060' $$,
  '42501', null, '다른 커플 사진은 대표 사진이 되지 못한다');
select throws_ok($$ insert into region_covers (couple_id, region_id, photo_id, scale, center_x, center_y)
  values ('10000000-0000-0000-0000-000000000001', '37020', '40000000-0000-0000-0000-000000000002', 0.2, 0.5, 0.5) $$,
  '23514', null, '0.25배보다 작은 배율은 거부한다');

-- 상대(b)도 바꿀 수 있고 나중 것이 남는다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
update region_covers set scale = 2, center_x = 0.5, center_y = 0.5 where region_id = '32060';
select ok((select scale = 2 and updated_by = '00000000-0000-0000-0000-0000000000b1' from region_covers where region_id = '32060'), '상대가 구도를 바꾼다');

-- 다른 커플은 읽지 못한다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select is((select count(*)::int from region_covers), 0, '다른 커플의 대표 사진은 읽지 못한다');

-- 여행에서 조각을 빼면 다른 조각에서 찍은 대표 사진을 해제한다.
reset role;
delete from trip_regions where trip_id = '30000000-0000-0000-0000-000000000001' and region_id = '31370';
select is((select count(*)::int from region_covers
  where couple_id = '10000000-0000-0000-0000-000000000001' and region_id = '31370'),
  0, '여행에서 조각을 빼면 다른 조각 사진은 대표에서 해제된다');

-- 사진을 지우면 대표 사진 행도 지워져 자동 대표로 돌아간다
delete from photos where id = '40000000-0000-0000-0000-000000000001';
select is((select count(*)::int from region_covers
  where couple_id = '10000000-0000-0000-0000-000000000001' and region_id = '32060'), 0, '사진을 지우면 대표 사진 행도 지워진다');
select has_table('public', 'region_covers', '테이블이 있다');

select * from finish();
rollback;
