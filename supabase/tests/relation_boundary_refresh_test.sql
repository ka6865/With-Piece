begin;
select plan(30);

insert into auth.users (id, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', '{"name":"하나"}'),
  ('00000000-0000-0000-0000-0000000000b1', '{"name":"두리"}');
insert into couples (id, user_a_id, user_b_id, started_on) values
  ('10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a1',
   '00000000-0000-0000-0000-0000000000b1', '2026-10-01');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001',
  home_region_id = '11010'
where id = '00000000-0000-0000-0000-0000000000a1';
update users set active_couple_id = '10000000-0000-0000-0000-000000000001',
  home_region_id = '26010'
where id = '00000000-0000-0000-0000-0000000000b1';
insert into photo_days (user_id, day, region_id, photo_count) values
  ('00000000-0000-0000-0000-0000000000a1', '2026-10-02', '11010', 2),
  ('00000000-0000-0000-0000-0000000000a1', '2026-10-06', '11010', 4);
insert into couple_region_overrides (couple_id, region_id, kind, updated_by) values
  ('10000000-0000-0000-0000-000000000001', '11010', 'home', '00000000-0000-0000-0000-0000000000a1'),
  ('10000000-0000-0000-0000-000000000001', '26010', 'travel', '00000000-0000-0000-0000-0000000000a1');
insert into photo_day_shares (couple_id, user_id, day, region_id) values
  ('10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a1', '2026-10-02', '11010'),
  ('10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a1', '2026-10-06', '11010');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select is((select count(*)::int from users), 1, 'users 직접 조회는 본인 행만 반환한다');
select results_eq(
  'select couple_id, partner_id, started_on, my_home_region_id from current_couple()',
  $$ values ('10000000-0000-0000-0000-000000000001'::uuid,
              '00000000-0000-0000-0000-0000000000b1'::uuid,
              '2026-10-01'::date, '11010'::text) $$,
  '현재 관계 RPC는 내 거주지와 상대 식별자만 반환한다');
select is((select count(*)::int from current_couple()), 1, '현재 관계 RPC는 한 행만 반환한다');
select lives_ok($$ select set_home_region('32060') $$, '거주지와 생활권을 함께 저장한다');
select is((select home_region_id from users where id = auth.uid()), '32060', '내 거주지를 변경한다');
select is((select count(*)::int from couple_region_overrides
  where couple_id = '10000000-0000-0000-0000-000000000001'
    and region_id = '32060' and kind = 'home' and updated_by = auth.uid()),
  1, '생활권 override가 같은 트랜잭션에 생긴다');
select is((select count(*)::int from couple_region_overrides
  where couple_id = '10000000-0000-0000-0000-000000000001' and kind = 'home'),
  2, '기존 home override를 보존한다');
select is((select count(*)::int from couple_region_overrides
  where couple_id = '10000000-0000-0000-0000-000000000001'
    and region_id = '26010' and kind = 'travel'),
  1, '수동 travel override를 보존한다');
select throws_ok($$ select set_started_on(null::date) $$, 'P0001', 'invalid_date',
  '기준일 NULL을 거부한다');
select throws_ok($$ select set_started_on('2999-01-01') $$, 'P0001', 'future_date',
  '미래 기준일을 거부한다');
select lives_ok($$ select set_started_on('2026-10-05') $$, '기준일을 늦춘다');
select is((select count(*)::int from photo_day_shares where day < '2026-10-05'), 0,
  '기준일 이전 승인을 즉시 삭제한다');
select is((select count(*)::int from photo_days where day < '2026-10-05'), 0,
  '기준일 이전 사진 일자를 즉시 삭제한다');
select lives_ok($$ select sync_photo_days(
  '10000000-0000-0000-0000-000000000001',
  '[{"day":"2026-10-02","region_id":"11010","photo_count":2},{"day":"2026-10-07","region_id":"11010","photo_count":3}]') $$,
  '오래된 스캔 스냅샷을 현재 기준일로 동기화한다');
select is((select count(*)::int from photo_days where day < '2026-10-05'), 0,
  '오래된 스캔이 기준일 이전 행을 되살리지 않는다');
select throws_ok($$ select update_photo_day_shares(
  '10000000-0000-0000-0000-000000000001',
  '[{"day":"2026-10-02","region_id":"11010","photo_count":2}]', '[]') $$,
  'P0001', 'invalid_share', '기준일 이전 승인은 거부한다');
select lives_ok($$ select request_refresh() $$, '최신화 요청을 저장한다');
select throws_ok($$ select request_refresh() $$, 'P0001', 'too_soon',
  '연속 요청은 원자적으로 제한한다');
select lives_ok($$ select update_photo_day_shares(
  '10000000-0000-0000-0000-000000000001',
  '[{"day":"2026-10-07","region_id":"11010","photo_count":3}]', '[]') $$,
  '새 기준일 이후의 승인을 저장한다');
select lives_ok($$ select set_started_on((now() at time zone 'Asia/Seoul')::date) $$,
  '서버가 UTC여도 한국의 오늘을 기준일로 저장한다');
select lives_ok($$ select archive_couple() $$, '연결을 끊고 이전 커플을 아카이브한다');
select is((select count(*)::int from current_couple()), 0, '아카이브 후 현재 관계가 없다');

reset role;
insert into couple_invites (inviter_id, code, expires_at) values
  ('00000000-0000-0000-0000-0000000000a1', 'rejoin001', now() + interval '1 day');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select is(join_couple('rejoin001'), 'ok', '이전 상대가 새 초대를 수락한다');
select isnt((select couple_id from current_couple()),
  '10000000-0000-0000-0000-000000000001'::uuid, '재결합은 새 커플 ID를 만든다');
select is((select started_on from current_couple()), null::date, '이전 기준일을 복원하지 않는다');
select is((select count(*)::int from couple_refresh_state
  where couple_id = (select couple_id from current_couple())), 0,
  '이전 최신화 상태를 새 커플로 옮기지 않는다');
select is((select count(*)::int from photo_day_shares
  where couple_id = (select couple_id from current_couple())), 0,
  '이전 승인 기록을 새 커플로 옮기지 않는다');
select throws_ok($$ insert into couple_region_overrides
  (couple_id, region_id, kind, updated_by)
  values ('10000000-0000-0000-0000-000000000001', '37020', 'travel', auth.uid()) $$,
  '42501', null, '이전 커플 기록은 다시 쓸 수 없다');
select is((select count(*)::int from users), 1, '상대의 현재 프로필은 직접 읽을 수 없다');
select results_eq(
  'select partner_name, partner_deletion_requested_at from archived_couples()',
  $$ values ('하나'::text, null::timestamptz) $$,
  '아카이브 상대 정보는 허용된 필드만 반환한다');

select * from finish();
rollback;
