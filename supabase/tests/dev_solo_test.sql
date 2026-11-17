-- 개발 전용(supabase/dev/solo_partner.sql). 로컬 스택에는 db reset 시드로 들어간다
begin;
select plan(7);

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000a1');
insert into photo_days values ('00000000-0000-0000-0000-0000000000a1', '2026-10-03', '32060', 2);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select is(dev_solo_join(), 'ok', '테스트 상대와 커플이 된다');
select is(dev_solo_join(), 'already_coupled', '이미 커플이면 다시 만들지 않는다');
select set_started_on('2026-01-01');
select replace_photo_day_shares(private.my_couple_id(), '[{"day":"2026-10-03","region_id":"32060"}]');
select results_eq('select day, region_id from couple_matched_days()',
  $$ values ('2026-10-03'::date, '32060'::text) $$, '이미 있던 내 기록이 상대에게 복사돼 교집합이 된다');

select lives_ok($$ select replace_photo_days('[
  {"day":"2026-10-04","region_id":"32400","photo_count":1}
]'::jsonb) $$, '내 목록을 바꾼다');
select replace_photo_day_shares(private.my_couple_id(), '[{"day":"2026-10-04","region_id":"32400"}]');
select results_eq('select day, region_id from couple_matched_days()',
  $$ values ('2026-10-04'::date, '32400'::text) $$, '상대 기록이 내 변경(추가·삭제)을 따라간다');
reset role;
select is((select raw_app_meta_data ->> 'dev_solo' from auth.users u
  join couples c on c.user_b_id = u.id
  where c.user_a_id = '00000000-0000-0000-0000-0000000000a1'), 'true', '테스트 상대는 표시가 붙은 계정이다');

set local role anon;
select throws_ok('select dev_solo_join()', '42501', null, '로그인하지 않으면 부를 수 없다');

select * from finish();
rollback;
