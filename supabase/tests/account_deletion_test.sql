begin;
select plan(16);

-- A·B 커플, B는 photo_days를 가진다. C는 31일 전에 삭제를 요청한 사용자
insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000d1');
insert into couples (id, user_a_id, user_b_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001'
  where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
insert into trips (id, couple_id, title, started_on, ended_on, status, source) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '속초', '2026-10-03', '2026-10-03', 'confirmed', 'manual');
insert into photo_days values
  ('00000000-0000-0000-0000-0000000000a1', '2026-10-03', '32060', 1),
  ('00000000-0000-0000-0000-0000000000b1', '2026-10-03', '32060', 1);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select lives_ok('select request_account_deletion()', 'A가 삭제를 요청한다');
reset role;
select isnt((select deletion_requested_at from users where id = '00000000-0000-0000-0000-0000000000a1'), null, '요청 시각이 남는다');
select is((select status from couples where id = '10000000-0000-0000-0000-000000000001'), 'archived', '커플이 아카이브된다');
select is((select count(*)::int from users where active_couple_id is not null
  and id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1')), 0, '두 사람 모두 활성 커플이 없다');
select is((select count(*)::int from photo_days where user_id = '00000000-0000-0000-0000-0000000000a1'), 0, 'A의 위치 기록은 바로 지운다');
select is((select count(*)::int from photo_days where user_id = '00000000-0000-0000-0000-0000000000b1'), 1, 'B의 기록은 남는다');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select is((select count(*)::int from trips), 1, '유예 중 상대는 여행을 읽는다');
select throws_ok($$ insert into trip_regions (trip_id, couple_id, region_id) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '32400') $$,
  '42501', null, '유예 중 상대는 쓰지 못한다');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select lives_ok('select cancel_account_deletion()', '다시 로그인한 A가 취소한다');
reset role;
select is((select deletion_requested_at from users where id = '00000000-0000-0000-0000-0000000000a1'), null, '요청 시각이 비워진다');
select is((select status from couples where id = '10000000-0000-0000-0000-000000000001'), 'archived', '커플은 되살리지 않는다');

-- 만료된 삭제: A를 31일 전 요청으로 만들고 사진을 둔다
update users set deletion_requested_at = now() - interval '31 days'
  where id = '00000000-0000-0000-0000-0000000000a1';
update users set deletion_requested_at = now() - interval '29 days'
  where id = '00000000-0000-0000-0000-0000000000c1';
insert into photos (id, trip_id, couple_id, object_key, width, height, byte_size, uploaded_by) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/p.heic', 1, 1, 1,
   '00000000-0000-0000-0000-0000000000b1');
select results_eq(
  'select user_id::text, object_paths from purge_expired_users()',
  $$ values ('00000000-0000-0000-0000-0000000000a1'::text, array[
    '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/full/p.heic',
    '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/thumb/p.heic']) $$,
  '30일 지난 사용자만, 그가 속한 커플의 사진(상대 사진 포함) 경로를 돌려준다');
select is((select count(*)::int from couples where id = '10000000-0000-0000-0000-000000000001'), 0, '커플 기록이 지워진다');
select is((select count(*)::int from photos where id = '40000000-0000-0000-0000-000000000001'), 0, '여행·사진 행도 함께 지워진다');

-- 고아 파일: 행이 없는 24시간 넘은 객체만
insert into storage.objects (bucket_id, name, created_at) values
  ('photos', '10000000-0000-0000-0000-000000000009/x/full/old.heic', now() - interval '2 days'),
  ('photos', '10000000-0000-0000-0000-000000000009/x/full/new.heic', now());
select results_eq('select * from orphan_photo_paths()',
  $$ values ('10000000-0000-0000-0000-000000000009/x/full/old.heic'::text) $$,
  '24시간 넘은 고아 파일만 고른다');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
select throws_ok('select * from purge_expired_users()', '42501', null, '로그인 사용자는 정리 함수를 부를 수 없다');

select * from finish();
rollback;
