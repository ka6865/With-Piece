begin;
select plan(25);

-- A·B 커플1, C·D 커플2, E 미소속. 준비는 postgres 권한으로 한다
insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c2'), ('00000000-0000-0000-0000-0000000000d2'),
  ('00000000-0000-0000-0000-0000000000e0');
insert into couples (id, user_a_id, user_b_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1'),
  ('20000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d2');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001'
  where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
update users set active_couple_id = '20000000-0000-0000-0000-000000000002'
  where id in ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d2');
insert into trips (id, couple_id, title, started_on, ended_on, status, source) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '속초', '2026-10-03', '2026-10-04', 'confirmed', 'auto'),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '경주', '2026-10-03', '2026-10-04', 'confirmed', 'auto');
insert into trip_regions (trip_id, couple_id, region_id) values
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '37020');
insert into photo_days values ('00000000-0000-0000-0000-0000000000a1', '2026-10-03', '32060', 3);
insert into storage.objects (bucket_id, name) values
  ('photos', '20000000-0000-0000-0000-000000000002/30000000-0000-0000-0000-000000000002/full/x.heic');

-- A로 전환
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select is((select count(*)::int from trips), 1, 'A는 자기 커플 여행만 본다');
select is((select count(*)::int from trip_regions), 0, 'A는 커플2 조각을 보지 못한다');
select is((select count(*)::int from couples), 1, 'A는 자기 커플만 본다');
select lives_ok($$ insert into trip_regions (trip_id, couple_id, region_id) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '32060') $$,
  'A는 자기 커플 여행에 조각을 넣는다');
select throws_ok($$ insert into trip_regions (trip_id, couple_id, region_id) values
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '32060') $$,
  '42501', null, '남의 couple_id로는 쓸 수 없다');
select throws_ok($$ insert into trip_regions (trip_id, couple_id, region_id) values
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '32410') $$,
  '23503', null, '남의 여행 id에 자기 couple_id를 붙여도 복합 외래키가 막는다');
select is((select count(*)::int from photo_days), 1, 'A는 자기 photo_days를 본다');
select is((select count(*)::int from users), 2, 'A는 자기와 B만 본다');
select throws_ok($$ update users set active_couple_id = null
  where id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501', null, 'active_couple_id는 직접 바꿀 수 없다');
select lives_ok($$ update users set nickname = '가'
  where id = '00000000-0000-0000-0000-0000000000a1' $$, '닉네임은 바꾼다');
select is((select count(*)::int from couple_invites), 0, '초대는 직접 읽을 수 없다');
select is((select count(*)::int from regions), 246, 'regions는 누구나 읽는다');

-- Storage
select lives_ok($$ insert into storage.objects (bucket_id, name) values
  ('photos', '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/full/a.heic') $$,
  '자기 커플 경로에는 올린다');
select throws_ok($$ insert into storage.objects (bucket_id, name) values
  ('photos', '20000000-0000-0000-0000-000000000002/x/full/a.heic') $$,
  '42501', null, '남의 커플 경로에는 올리지 못한다');
select throws_ok($$ insert into storage.objects (bucket_id, name) values
  ('photos', 'not-a-uuid/x/full/a.heic') $$,
  '22P02', null, '첫 세그먼트가 uuid가 아니면 거부');
select is((select count(*)::int from storage.objects where bucket_id = 'photos'
  and name like '20000000%'), 0, '남의 커플 사진을 보지 못한다');
select lives_ok($$ insert into storage.objects (bucket_id, name) values
  ('photos', '10000000-0000-0000-0000-000000000001/../20000000-0000-0000-0000-000000000002/y.heic') $$,
  '..이 든 이름도 자기 커플 영역의 객체로 생긴다');

-- B: 상대의 photo_days를 보지 못한다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select is((select count(*)::int from photo_days), 0, 'B는 A의 photo_days를 보지 못한다');

-- C: .. 이름의 객체는 커플2에게 보이지 않는다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c2","role":"authenticated"}', true);
select is((select count(*)::int from storage.objects where bucket_id = 'photos'), 1,
  'C는 자기 커플 사진 하나만 본다');

-- E: 미소속
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e0","role":"authenticated"}', true);
select is((select count(*)::int from trips), 0, 'E는 여행을 보지 못한다');
select throws_ok($$ insert into trips (couple_id, title, started_on, ended_on, status, source) values
  ('10000000-0000-0000-0000-000000000001', 't', '2026-01-01', '2026-01-01', 'confirmed', 'manual') $$,
  '42501', null, 'E는 쓸 수 없다(my_couple_id가 NULL)');

-- 아카이브 뒤 A는 읽기만 된다
reset role;
update couples set status = 'archived', archived_at = now()
  where id = '10000000-0000-0000-0000-000000000001';
update users set active_couple_id = null
  where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select is((select count(*)::int from trips), 1, '아카이브 뒤에도 읽는다');
select throws_ok($$ insert into trip_regions (trip_id, couple_id, region_id) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '32410') $$,
  '42501', null, '아카이브 뒤에는 쓰지 못한다');

-- anon은 커플 데이터를 보지 못한다
set local role anon;
select is((select count(*)::int from trips), 0, 'anon은 여행을 보지 못한다');
select is((select count(*)::int from regions), 246, 'anon도 regions는 읽는다');

select * from finish();
rollback;
