begin;
select plan(12);

insert into auth.users (id) values
 ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1');
insert into couples (id, user_a_id, user_b_id, started_on) values
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1', '2026-10-05');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001'
 where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
insert into trips (id, couple_id, title, started_on, ended_on, status, source) values
 ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '여행', '2026-10-05', '2026-10-05', 'confirmed', 'manual');

select set_config('request.jwt.claims','{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}',true);
select is(photo_upload_limit('10000000-0000-0000-0000-000000000001'), 1000, '기본 한도는 1000장');
select lives_ok($$insert into photos (trip_id, couple_id, object_key, width, height, byte_size, taken_at)
 values ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/a.heic',1,1,1,null)$$, '촬영일 없는 기존 수동 입력은 허용');
select throws_ok($$insert into photos (trip_id, couple_id, object_key, width, height, byte_size, taken_at)
 values ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/b.heic',1,1,1,'2026-10-04 14:59:59+00')$$,
 'P0001', 'photo_before_started_on', '한국 시간 기준 시작일 전 사진 거부');
select is((select count(*)::int from photos), 1, '기준일 거부가 사진 행을 만들지 않음');
select is((select photo_count::text from photo_usage('10000000-0000-0000-0000-000000000001')), '1', '사용량은 현재 사진 수');
select throws_ok($$select photo_upload_limit(null)$$, 'P0001', 'no_active_couple', 'NULL 커플 ID를 거부');
insert into private.couple_photo_quota_overrides (couple_id, photo_limit)
 values ('10000000-0000-0000-0000-000000000001', 1);
select is(photo_upload_limit('10000000-0000-0000-0000-000000000001'), 1, '커플별 한도가 기본값을 덮어씀');
select throws_ok($$insert into photos (trip_id, couple_id, object_key, width, height, byte_size, taken_at)
 values ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/c.heic',1,1,1,'2026-10-05 00:00:00+09')$$,
 'P0001', 'photo_limit_exceeded', '커플 한도 초과 insert를 거부');
select is((select count(*)::int from photos), 1, '한도 초과가 사진 행을 만들지 않음');
select ok((select relrowsecurity from pg_class where oid = 'private.photo_quota_defaults'::regclass), '기본 한도 테이블 RLS 활성');
select ok((select relrowsecurity from pg_class where oid = 'private.couple_photo_quota_overrides'::regclass), '커플 한도 테이블 RLS 활성');
select is(has_table_privilege('authenticated', 'private.photo_quota_defaults', 'select'), false, '인증 사용자는 기본 한도 테이블을 직접 읽지 못함');
select * from finish();
rollback;
