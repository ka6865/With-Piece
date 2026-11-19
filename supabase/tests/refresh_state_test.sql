begin;
select plan(12);

-- a·b 커플(사귄 날 있음), c·d 다른 커플
insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000d1');
insert into couples (id, user_a_id, user_b_id, started_on) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', '2026-01-01'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1', '2026-01-01');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001'
  where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
update users set active_couple_id = '10000000-0000-0000-0000-000000000002'
  where id in ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select lives_ok($$ select request_refresh() $$, '상대에게 최신화를 요청한다');
select is(
  (select requested_by from couple_refresh_state where user_id = '00000000-0000-0000-0000-0000000000b1'),
  '00000000-0000-0000-0000-0000000000a1'::uuid, '요청은 상대 행에 보낸 사람과 함께 남는다');
select throws_ok($$ select request_refresh() $$, 'P0001', 'too_soon', '1시간 안에는 다시 요청하지 못한다');
select throws_ok($$ insert into couple_refresh_state (couple_id, user_id, refreshed_at)
  values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', now()) $$,
  '42501', null, '행을 직접 쓰지 못한다');

-- 1시간이 지나면 다시 요청할 수 있다
reset role;
update couple_refresh_state set requested_at = now() - interval '2 hours',
  last_requested_at = now() - interval '2 hours';
set local role authenticated;
select lives_ok($$ select request_refresh() $$, '1시간이 지나면 다시 요청한다');

-- 받은 사람(b)은 두 사람 행을 읽고, 비교 기록을 저장하면 최신화로 남고 요청이 지워진다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select is((select count(*)::int from couple_refresh_state), 1, '커플 행을 읽는다');
select lives_ok($$ select mark_refreshed() $$, '비교 기록을 저장한 뒤 최신화를 남긴다');
select ok(
  (select refreshed_at is not null and requested_at is null and requested_by is null
   from couple_refresh_state where user_id = '00000000-0000-0000-0000-0000000000b1'),
  '최신화 시각이 남고 받은 요청이 지워진다');

-- 상대가 처리한 뒤에도 보낸 시각부터 1시간 동안 제한한다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select throws_ok($$ select request_refresh() $$, 'P0001', 'too_soon',
  '최신화가 끝나도 마지막 요청부터 1시간 동안 다시 보낼 수 없다');

-- 다른 커플은 읽지 못한다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select is((select count(*)::int from couple_refresh_state), 0, '다른 커플 행은 읽지 못한다');

-- 연결을 끊으면 요청하지 못한다
reset role;
update users set active_couple_id = null where id = '00000000-0000-0000-0000-0000000000a1';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select throws_ok($$ select request_refresh() $$, 'P0001', 'no_active_couple', '활성 커플이 없으면 요청하지 못한다');
select is((select count(*)::int from couple_refresh_state), 1, '지난 커플 행은 읽는다');

select * from finish();
rollback;
