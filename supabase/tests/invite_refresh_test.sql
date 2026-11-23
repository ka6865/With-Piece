begin;
select plan(10);

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1');

set local role authenticated;

-- A와 B가 둘 다 코드를 만든 뒤 B가 A의 코드로 연결한다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
create temp table a_inv on commit drop as select * from create_invite();
select ok((select expires_at between now() + interval '3 days' - interval '1 minute'
  and now() + interval '3 days' + interval '1 minute' from a_inv), '만료는 3일 뒤');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
create temp table b_inv on commit drop as select * from create_invite();
select is(join_couple((select code from a_inv)), 'ok', 'B가 A의 코드로 연결한다');
select is((select count(*)::int from my_invite()), 0, '연결되면 B가 만들어 둔 코드도 사라진다');

-- 끊은 뒤 A가 예전에 받은 B의 코드로 다시 연결하지 못한다
select lives_ok('select archive_couple()', 'B가 연결을 끊는다');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select is(join_couple((select code from b_inv)), 'invalid_code', '옛 코드로는 다시 연결되지 않는다');

-- 새로고침하면 새 코드가 나오고 옛 코드는 바로 무효다
create temp table a_old on commit drop as select * from create_invite();
create temp table a_new on commit drop as select * from regenerate_invite();
select isnt((select code from a_new), (select code from a_old), '새로고침하면 코드가 바뀐다');
select is((select code from my_invite()), (select code from a_new), 'my_invite는 새 코드다');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select is(join_couple((select code from a_old)), 'invalid_code', '새로고침 전 코드는 무효다');

-- 커플이면 새로고침할 수 없다
select is(join_couple((select code from a_new)), 'ok', 'C가 새 코드로 연결한다');
select throws_ok('select * from regenerate_invite()', 'P0001', 'already_coupled', '커플이면 새로고침할 수 없다');

select * from finish();
rollback;
