begin;
select plan(13);
insert into auth.users (id) values
 ('00000000-0000-0000-0000-0000000000a1'),
 ('00000000-0000-0000-0000-0000000000b1');
insert into couples (id, user_a_id, user_b_id, started_on) values
 ('10000000-0000-0000-0000-000000000001',
 '00000000-0000-0000-0000-0000000000a1',
 '00000000-0000-0000-0000-0000000000b1', '2026-01-01');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001';
insert into photo_days values
 ('00000000-0000-0000-0000-0000000000a1', '2026-10-03', '32060', 1),
 ('00000000-0000-0000-0000-0000000000a1', '2026-10-04', '32400', 1),
 ('00000000-0000-0000-0000-0000000000a1', '2025-12-31', '32060', 1),
 ('00000000-0000-0000-0000-0000000000b1', '2026-10-03', '32060', 1),
 ('00000000-0000-0000-0000-0000000000b1', '2026-10-04', '32400', 1);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select is((select count(*)::int from couple_matched_days()), 0,
 '같은 사진 날짜·지역이어도 기본값은 비교 미승인이다');
select throws_ok($$ select replace_photo_day_shares('10000000-0000-0000-0000-000000000099', '[]') $$,
 'P0001', 'no_active_couple', '이전 커플 화면에서 새 커플로 승인 범위를 옮기지 않는다');
select lives_ok($$ select replace_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-03","region_id":"32060"}]') $$,
 '내 기록 중 비교할 날짜·지역만 승인한다');
select is((select count(*)::int from couple_matched_days()), 0, '한 사람 승인만으로는 비교하지 않는다');
select throws_ok($$ select replace_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-05","region_id":"32060"}]') $$,
 'P0001', 'invalid_share', '본인 원본에 없는 기록 승인 거부');
select throws_ok($$ select replace_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2025-12-31","region_id":"32060"}]') $$,
 'P0001', 'invalid_share', '사귄 날 이전 기록 승인 거부');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select is((select count(*)::int from photo_day_shares), 0, '상대 승인 목록 직접 열람 거부');
select lives_ok($$ select replace_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-03","region_id":"32060"},{"day":"2026-10-04","region_id":"32400"}]') $$,
 '상대가 조회 범위를 넓혀도 자기 목록만 바뀐다');
select results_eq('select day, region_id from couple_matched_days()',
 $$ values ('2026-10-03'::date,'32060'::text) $$,
 '상대의 승인하지 않은 단독 기록은 조작한 비교 목록에도 노출되지 않는다');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select replace_photo_day_shares('10000000-0000-0000-0000-000000000001', '[]');
select is((select count(*)::int from couple_matched_days()), 0, '승인 철회 즉시 비교 대상에서 빠진다');
select replace_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-03","region_id":"32060"}]');
delete from photo_days where day = '2026-10-03';
select is((select count(*)::int from photo_day_shares), 0, '원본 삭제는 승인도 삭제한다');
select archive_couple();
select throws_ok($$ select replace_photo_day_shares('10000000-0000-0000-0000-000000000001', '[]') $$,
 'P0001', 'no_active_couple', '아카이브 상태에서 승인 변경 거부');
reset role;
select ok((select relrowsecurity from pg_class where oid = 'public.photo_day_shares'::regclass), '승인 테이블 RLS 활성화');
select * from finish();
rollback;
