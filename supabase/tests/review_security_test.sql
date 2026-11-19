begin;
select plan(17);

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000e1'), ('00000000-0000-0000-0000-0000000000f1');
insert into couples (id, user_a_id, user_b_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001'
where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
insert into trips (id, couple_id, title, started_on, ended_on, status, source) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '속초', '2026-10-03', '2026-10-03', 'confirmed', 'manual');
insert into photos (id, trip_id, couple_id, object_key, width, height, byte_size, uploaded_by) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/p.heic',
   1, 1, 1, '00000000-0000-0000-0000-0000000000a1');

insert into couple_invites (inviter_id, code, expires_at) values
  ('00000000-0000-0000-0000-0000000000d1', 'pendinginv1', now() + interval '1 day'),
  ('00000000-0000-0000-0000-0000000000e1', 'validinv01', now() + interval '1 day');
update users set deletion_requested_at = now() where id in
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
update photos set object_key = '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/changed.heic',
  uploaded_by = '00000000-0000-0000-0000-0000000000b1'
where id = '40000000-0000-0000-0000-000000000001';
reset role;
select is((select object_key from photos where id = '40000000-0000-0000-0000-000000000001'),
  '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/p.heic', '사진 경로와 소유자는 클라이언트가 바꾸지 못한다');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select throws_ok($$ insert into photos (trip_id, couple_id, object_key, width, height, byte_size, uploaded_by)
  values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/forged.heic', 1, 1, 1,
  '00000000-0000-0000-0000-0000000000b1') $$, '42501', null, '사진 업로더를 위조하지 못한다');
select is((select created_by from trips where title = '속초'), null::uuid, '기존 작성자 정보는 기본값을 유지한다');
select lives_ok($$ insert into couple_region_overrides (couple_id, region_id, kind)
  values ('10000000-0000-0000-0000-000000000001', '32060', 'home') $$, '공동 생활권을 기록한다');
select is((select updated_by from couple_region_overrides where region_id = '32060'),
  '00000000-0000-0000-0000-0000000000a1'::uuid, '직접 기록해도 서버가 작성자를 설정한다');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000d1","role":"authenticated"}', true);
select throws_ok('select * from create_invite()', 'P0001', 'deletion_pending', '삭제 유예 중 초대를 만들지 못한다');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select is(join_couple('validinv01'), 'deletion_pending', '삭제 유예 중인 사용자는 합류하지 못한다');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000f1","role":"authenticated"}', true);
select is(join_couple('pendinginv1'), 'deletion_pending', '삭제 유예 중인 초대 발급자에게 합류하지 못한다');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select lives_ok('select request_account_deletion()', '삭제 요청이 처리된다');
create temp table original_request as select deletion_requested_at as requested_at from users
  where id = '00000000-0000-0000-0000-0000000000a1';
select pg_sleep(0.01);
select lives_ok('select request_account_deletion()', '중복 삭제 요청은 허용된다');
reset role;
select is((select deletion_requested_at from users where id = '00000000-0000-0000-0000-0000000000a1'),
  (select requested_at from original_request), '중복 요청으로 유예 기간이 연장되지 않는다');

update users set deletion_requested_at = now() - interval '31 days'
where id = '00000000-0000-0000-0000-0000000000a1';
select results_eq('select user_id::text from purge_expired_users()',
  $$ values ('00000000-0000-0000-0000-0000000000a1'::text) $$, '정리 시작 사용자를 반환한다');
select is((select count(*)::int from photos where id = '40000000-0000-0000-0000-000000000001'), 1,
  'Storage 삭제 전 DB 사진 메타데이터를 보존한다');
select is((select count(*)::int from purge_expired_users()), 1, '부분 실패 후 같은 정리 작업을 재시도할 수 있다');
select throws_ok($$ select cancel_account_deletion() $$, 'P0001', 'deletion_started', '정리 시작 뒤 취소를 거부한다');
select lives_ok($$ select finalize_expired_user('00000000-0000-0000-0000-0000000000a1') $$, 'Storage 삭제 뒤 DB 정리를 완료한다');
select is((select active_couple_id from users where id = '00000000-0000-0000-0000-0000000000b1'), null::uuid, '상대 사용자의 활성 커플 참조를 먼저 비운다');

select * from finish();
rollback;
