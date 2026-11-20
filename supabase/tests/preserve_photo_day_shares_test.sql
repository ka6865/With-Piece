begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(25);
insert into auth.users (id) values
 ('00000000-0000-0000-0000-0000000000a1'),
 ('00000000-0000-0000-0000-0000000000b1');
insert into couples (id, user_a_id, user_b_id, started_on) values
 ('10000000-0000-0000-0000-000000000001',
 '00000000-0000-0000-0000-0000000000a1',
 '00000000-0000-0000-0000-0000000000b1', '2026-01-01');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001'
where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
-- 기기 A의 앞선 승인 이후 기기 B가 자기 스냅샷을 동기화한다.
select sync_photo_days('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-03","region_id":"32060","photo_count":4},{"day":"2026-10-02","region_id":"11010","photo_count":1}]');
select update_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-03","region_id":"32060","photo_count":4}]', '[]');
select lives_ok($$ select sync_photo_days('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-04","region_id":"32400","photo_count":2}]') $$,
 '기기 B가 다른 스냅샷을 동기화한다');
select is((select count(*)::int from photo_day_shares), 1, '기기 A에서 승인한 원본과 승인을 보존한다');
select results_eq('select day, photo_count from photo_days order by day',
 $$ values ('2026-10-03'::date,4) $$, '구버전 기기 스캔은 미승인 원본을 추가하지 않는다');
select sync_photo_days('10000000-0000-0000-0000-000000000001', '[]');
select is((select count(*)::int from photo_days), 1, '같은 기기의 전체 재스캔에서도 승인한 원본을 보존한다');
select sync_photo_days('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-03","region_id":"32060","photo_count":1}]');
select is((select photo_count from photo_days where day = '2026-10-03'), 4, '구버전 스캔은 승인한 장수를 덮어쓰지 못한다');
select sync_photo_days('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-04","region_id":"32400","photo_count":2}]');
select update_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-04","region_id":"32400","photo_count":2}]', '[]');
-- 기기 A가 보지 못했던 기기 B의 승인을 남긴 채 기존 승인만 철회한다.
select update_photo_day_shares('10000000-0000-0000-0000-000000000001', '[]', '[{"day":"2026-10-03","region_id":"32060"}]');
select results_eq('select day from photo_day_shares order by day', $$ values ('2026-10-04'::date) $$, '다른 기기에서 나중에 승인한 기록은 수정하지 않는다');
select results_eq('select day from photo_days order by day', $$ values ('2026-10-04'::date) $$, '마지막 승인을 철회하면 그 원본을 즉시 제거한다');
select throws_ok($$ select sync_photo_days('10000000-0000-0000-0000-000000000099', '[]') $$,
 'P0001','no_active_couple','다른 커플에서 동기화하지 못한다');
-- 기기 B의 동기화가 지운 미승인 원본을 기기 A가 자기 스냅샷 장수로 승인한다.
select lives_ok($$ select update_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-02","region_id":"11010","photo_count":1}]', '[]') $$,
 '다른 기기 동기화로 빠진 원본도 승인할 수 있다');
select results_eq('select day, photo_count from photo_days order by day',
 $$ values ('2026-10-02'::date,1), ('2026-10-04'::date,2) $$, '승인과 함께 원본을 다시 맞춘다');
select update_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-04","region_id":"32400","photo_count":1}]', '[]');
select is((select photo_count from photo_days where day = '2026-10-04'), 2,
 '이미 있는 원본의 장수는 오래된 승인 화면 값으로 덮지 않는다');
select update_photo_day_shares('10000000-0000-0000-0000-000000000001', '[]', '[{"day":"2026-10-02","region_id":"11010"}]');
select sync_photo_days('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-04","region_id":"32400","photo_count":2}]');
select throws_ok($$ select update_photo_day_shares('10000000-0000-0000-0000-000000000099', '[]', '[]') $$,
 'P0001','no_active_couple','다른 커플의 승인을 수정하지 못한다');
select throws_ok($$ select sync_photo_days('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-05","region_id":"32060","photo_count":0}]') $$,
 'P0001','invalid_photo_days','잘못된 장수는 원본을 삭제하기 전에 거부한다');
select throws_ok($$ select update_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-05","region_id":"32060"}]', '[{"day":"2026-10-04","region_id":"32400"}]') $$,
 'P0001','invalid_share','장수 없는 승인은 철회도 반영하지 않고 거부한다');
select is((select count(*)::int from photo_day_shares), 1, '실패한 변경은 앞선 승인을 유지한다');
select set_started_on('2026-10-05');
select lives_ok($$ select update_photo_day_shares('10000000-0000-0000-0000-000000000001', '[]', '[{"day":"2026-10-04","region_id":"32400"}]') $$,
 '기준일 이전의 오래된 승인 철회는 유효하다');
select sync_photo_days('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-04","region_id":"32400","photo_count":2},{"day":"2026-10-05","region_id":"32060","photo_count":3}]');
select is((select count(*)::int from photo_days), 0, '구버전 스캔은 기준일 전후 어느 원본도 저장하지 않는다');
select set_started_on('2026-01-01');
select update_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-05","region_id":"32060","photo_count":3}]', '[]');
select set_started_on('2026-10-06');
select sync_photo_days('10000000-0000-0000-0000-000000000001', '[]');
select is((select count(*)::int from photo_day_shares), 0, '기준일 이후로 변경하면 승인된 원본도 삭제하고 승인을 연쇄 삭제한다');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select is((select count(*)::int from photo_days), 0, '상대 원본은 RLS로 열람할 수 없다');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select set_started_on('2026-01-01');
select sync_photo_days('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-05","region_id":"32060","photo_count":3}]');
select update_photo_day_shares('10000000-0000-0000-0000-000000000001', '[{"day":"2026-10-05","region_id":"32060","photo_count":3}]', '[]');
select request_account_deletion();
select is((select count(*)::int from photo_days), 0, '계정 삭제 요청은 승인된 원본도 즉시 제거한다');
select is((select count(*)::int from photo_day_shares), 0, '계정 삭제 요청은 승인도 연쇄 삭제한다');
select throws_ok($$ select sync_photo_days('10000000-0000-0000-0000-000000000001', '[]') $$,
 'P0001','no_active_couple','계정 삭제 후 동기화로 원본을 복구하지 못한다');
reset role;
select ok(not has_function_privilege('anon', 'public.sync_photo_days(uuid,jsonb)', 'EXECUTE')
 and not has_function_privilege('anon', 'public.update_photo_day_shares(uuid,jsonb,jsonb)', 'EXECUTE'), '익명 RPC 실행 금지');
-- 관계가 삭제돼 참조가 사라지면 다른 관계가 쓰는 원본만 유지한다.
insert into couples (id, user_a_id, user_b_id, started_on, status, archived_at) values
 ('10000000-0000-0000-0000-000000000002',
 '00000000-0000-0000-0000-0000000000a1',
 '00000000-0000-0000-0000-0000000000b1', '2026-01-01', 'archived', now()),
 ('10000000-0000-0000-0000-000000000003',
 '00000000-0000-0000-0000-0000000000a1',
 '00000000-0000-0000-0000-0000000000b1', '2026-01-01', 'archived', now());
insert into photo_days (user_id, day, region_id, photo_count) values
 ('00000000-0000-0000-0000-0000000000b1', '2026-10-11', '32060', 8);
insert into photo_day_shares (couple_id, user_id, day, region_id) values
 ('10000000-0000-0000-0000-000000000002',
 '00000000-0000-0000-0000-0000000000b1', '2026-10-11', '32060'),
 ('10000000-0000-0000-0000-000000000003',
 '00000000-0000-0000-0000-0000000000b1', '2026-10-11', '32060');
delete from couples where id = '10000000-0000-0000-0000-000000000002';
select is((select count(*)::int from photo_days where day = '2026-10-11'), 1,
  '다른 지난 관계에서 쓰는 원본은 관계 정리로 제거하지 않는다');
delete from couples where id = '10000000-0000-0000-0000-000000000003';
select is((select count(*)::int from photo_days where day = '2026-10-11'), 0,
  '마지막 참조가 있던 지난 관계가 정리되면 집계도 삭제한다');
select * from finish();
rollback;
