begin;
select plan(23);

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000d1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

-- 초대 발급
create temp table invite on commit drop as select * from create_invite();
select matches((select code from invite), '^[2-9A-HJ-NP-Za-km-np-z]{10}$', '혼동 문자를 뺀 56자 중 10자');
select ok((select expires_at between now() + interval '7 days' - interval '1 minute'
  and now() + interval '7 days' + interval '1 minute' from invite), '만료는 7일 뒤');
select is((select code from create_invite()), (select code from invite), '미수락 초대가 있으면 같은 코드');
select is((select code from my_invite()), (select code from invite), 'my_invite가 내 초대를 돌려준다');

-- 자기 코드, 없는 코드
select is(join_couple((select code from invite)), 'self', '자기 코드는 self');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select is(join_couple('zzzzzzzzzz'), 'invalid_code', '없는 코드는 invalid_code');

-- 합류
select is(join_couple((select code from invite)), 'ok', 'B가 합류한다');
select is((select count(*)::int from couples), 1, '커플 행 1개');
reset role;
select is((select count(distinct active_couple_id)::int from users
  where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1')
    and active_couple_id is not null), 1, '두 사람이 같은 활성 커플을 가진다');
select isnt((select accepted_at from couple_invites where code = (select code from invite)),
  null, '초대가 수락 처리된다');

-- 이미 커플이면 초대 발급·합류 불가
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select throws_ok('select * from create_invite()', 'P0001', 'already_coupled', '커플이 있으면 초대를 만들 수 없다');

-- C의 초대에 A가 합류 시도 → already_coupled
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
create temp table c_invite on commit drop as select * from create_invite();
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select is(join_couple((select code from c_invite)), 'already_coupled', '이미 커플이면 already_coupled');

-- 만료된 초대
reset role;
update couple_invites set expires_at = now() - interval '1 second' where code = (select code from c_invite);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
select is(join_couple((select code from c_invite)), 'expired', '만료는 expired');

-- 만료된 미수락 초대는 지우고 새로 만든다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
create temp table c_invite2 on commit drop as select * from create_invite();
select isnt((select code from c_invite2), (select code from c_invite), '만료 초대 대신 새 코드');

-- 속도 제한: D는 이미 실패 1회(expired). 4회 더 실패하면 올바른 코드도 rate_limited
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
select is(join_couple('zzzzzzzzz1'), 'invalid_code', '실패 2');
select is(join_couple('zzzzzzzzz2'), 'invalid_code', '실패 3');
select is(join_couple('zzzzzzzzz3'), 'invalid_code', '실패 4');
select is(join_couple('zzzzzzzzz4'), 'invalid_code', '실패 5');
select is(join_couple((select code from c_invite2)),
  'rate_limited', '1분 안 5회 실패 뒤에는 올바른 코드도 rate_limited');

-- 사귄 날과 교집합
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select is((select count(*)::int from couple_matched_days()), 0, '사귄 날이 없으면 교집합 없음');
select throws_ok($$ select set_started_on((now() at time zone 'Asia/Seoul')::date + 1) $$,
  'P0001', 'future_date', '한국 날짜의 미래 기준일을 거부한다');
select set_started_on('2026-01-01');
reset role;
insert into photo_days values
  ('00000000-0000-0000-0000-0000000000a1', '2025-12-31', '32060', 1),
  ('00000000-0000-0000-0000-0000000000b1', '2025-12-31', '32060', 1),
  ('00000000-0000-0000-0000-0000000000a1', '2026-10-03', '32060', 4),
  ('00000000-0000-0000-0000-0000000000b1', '2026-10-03', '32060', 2),
  ('00000000-0000-0000-0000-0000000000a1', '2026-10-04', '32400', 1),
  ('00000000-0000-0000-0000-0000000000b1', '2026-10-04', '32410', 1);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
reset role;
insert into photo_day_shares(couple_id, user_id, day, region_id)
 select u.active_couple_id, d.user_id, d.day, d.region_id
 from photo_days d join users u on u.id = d.user_id
 where u.active_couple_id is not null and d.day >= '2026-01-01'
   and d.user_id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1')
 on conflict do nothing;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select results_eq('select day, region_id from couple_matched_days()',
  $$ values ('2026-10-03'::date, '32060'::text) $$,
  '두 사람 모두 있는 날·조각만, 사귄 날 이후만');

-- 아카이브
select archive_couple();
reset role;
select is((select count(*)::int from users where active_couple_id is not null
  and id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1')),
  0, '아카이브 뒤 두 사람 모두 활성 커플이 없다');

select * from finish();
rollback;
