begin;
select plan(10);

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000e0');
insert into couples (id, user_a_id, user_b_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001'
  where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select isnt(confirm_trip('속초시 고성군 1박 2일', '2026-10-03', '2026-10-04', array['32060', '32400'], 'auto'),
  null, '확인하면 여행 id를 돌려준다');
select is((select count(*)::int from trip_regions), 2, '조각 두 개가 함께 생긴다');
select results_eq('select status, source, created_by::text from trips',
  $$ values ('confirmed'::text, 'auto'::text, '00000000-0000-0000-0000-0000000000a1'::text) $$, '확인된 자동 여행');

select throws_ok($$ select confirm_trip('x', '2026-10-03', '2026-10-04', array['32060'], 'auto') $$,
  '23505', null, '같은 기간의 자동 여행은 한 번만 확인된다');
select throws_ok($$ select confirm_trip('x', '2026-11-01', '2026-11-01', array[]::text[], 'manual') $$,
  'P0001', 'empty_regions', '조각이 없으면 거부');
select throws_ok($$ select confirm_trip('x', '2026-11-01', '2026-11-01', array['99999'], 'manual') $$,
  '23503', null, '없는 조각 코드는 거부');
select is((select count(*)::int from trips), 1, '실패한 확인은 여행을 남기지 않는다');

select isnt(dismiss_trip('2026-03-01', '2026-03-02'), null, '버리면 기간만 남긴다');
select is((select count(*)::int from couple_visited_regions), 2, '버린 여행은 진행률에 들어가지 않는다');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000e0","role":"authenticated"}', true);
select throws_ok($$ select confirm_trip('x', '2026-11-01', '2026-11-01', array['32060'], 'manual') $$,
  'P0001', 'no_active_couple', '커플이 없으면 거부');

select * from finish();
rollback;
