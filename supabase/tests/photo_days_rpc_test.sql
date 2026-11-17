begin;
select plan(5);

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1');
insert into photo_days values
  ('00000000-0000-0000-0000-0000000000a1', '2026-01-01', '11010', 1),
  ('00000000-0000-0000-0000-0000000000a1', '2026-10-03', '32060', 1),
  ('00000000-0000-0000-0000-0000000000b1', '2026-10-03', '32060', 7);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select lives_ok($$ select replace_photo_days('[
  {"day":"2026-10-03","region_id":"32060","photo_count":4},
  {"day":"2026-10-04","region_id":"32400","photo_count":2}
]'::jsonb) $$, '내 목록을 주어진 목록으로 바꾼다');

select results_eq(
  'select day, region_id, photo_count from photo_days order by day',
  $$ values ('2026-10-03'::date, '32060'::text, 4), ('2026-10-04'::date, '32400'::text, 2) $$,
  '없는 행은 지우고 있는 행은 장수를 바꾸고 새 행을 넣는다');

select lives_ok($$ select replace_photo_days('[]'::jsonb) $$, '빈 목록이면 내 행을 모두 지운다');
select is((select count(*)::int from photo_days), 0, '내 행이 없다');

reset role;
select is((select photo_count from photo_days
  where user_id = '00000000-0000-0000-0000-0000000000b1'), 7, '상대의 행은 건드리지 않는다');

select * from finish();
rollback;
