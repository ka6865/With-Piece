begin;
select plan(17);
select is(
  (select count(*)::int from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'),
  0, '행 DELETE를 어느 구독자에게도 발행하지 않는다');
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public' and c.relname in ('photos', 'trip_regions', 'couple_region_overrides', 'trips', 'couples') and c.relreplident = 'd'),
 5, '비공개 알림 전환 후 복제 식별자를 기본값으로 되돌린다');
select ok((select relrowsecurity from pg_class where oid = 'realtime.messages'::regclass),
 '비공개 알림 RLS가 활성화되어 있다');
insert into auth.users(id) values
 ('00000000-0000-0000-0000-0000000000a1'),
 ('00000000-0000-0000-0000-0000000000b1'),
 ('00000000-0000-0000-0000-0000000000c1'),
 ('00000000-0000-0000-0000-0000000000d1');
insert into couples(id, user_a_id, user_b_id, started_on) values
 ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1',
 '00000000-0000-0000-0000-0000000000b1', '2026-01-01'),
 ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000c1',
 '00000000-0000-0000-0000-0000000000d1', '2026-01-01');
update users set active_couple_id = '10000000-0000-0000-0000-000000000002'
 where id in ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001'
 where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
insert into photo_days values
 ('00000000-0000-0000-0000-0000000000a1', '2026-10-03', '32060', 1),
 ('00000000-0000-0000-0000-0000000000a1', '2026-10-04', '32400', 1);
insert into photo_day_shares select '10000000-0000-0000-0000-000000000001', user_id, day, region_id from photo_days
 where user_id = '00000000-0000-0000-0000-0000000000a1';
select is((select count(*)::int from realtime.messages
 where topic = 'couple-shares:10000000-0000-0000-0000-000000000001' and event = 'shares'),
 1, '여러 승인 행을 넣어도 문장당 알림은 하나다');
delete from photo_days where user_id = '00000000-0000-0000-0000-0000000000a1';
select is((select count(*)::int from realtime.messages
 where topic = 'couple-shares:10000000-0000-0000-0000-000000000001' and event = 'shares'),
 2, '원본 일괄 삭제의 FK 연쇄 삭제도 하나의 알림을 보낸다');
select ok(not exists(select 1 from realtime.messages
 where topic in ('couple:10000000-0000-0000-0000-000000000001',
 'couple-shares:10000000-0000-0000-0000-000000000001',
 'user:00000000-0000-0000-0000-0000000000a1', 'user:00000000-0000-0000-0000-0000000000b1')
 and (not private or payload - 'id' <> '{}'::jsonb)), '행 정보 없이 helper가 생성한 메시지 ID만 보낸다');
update users set nickname = '이름' where id = '00000000-0000-0000-0000-0000000000a1';
select is((select count(*)::int from realtime.messages
 where topic = 'user:00000000-0000-0000-0000-0000000000a1'), 1,
 '프로필 변경은 커플 연결 알림을 만들지 않는다');
select is((select count(*)::int from pg_policies where schemaname = 'realtime'
 and tablename = 'messages' and cmd <> 'SELECT'), 0, '클라이언트 발신 권한은 추가하지 않는다');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select set_config('realtime.topic', 'couple:10000000-0000-0000-0000-000000000001', true);
select is((select count(*)::int from realtime.messages), 1, '멤버는 소속 커플 알림을 읽는다');
select set_config('realtime.topic', 'user:00000000-0000-0000-0000-0000000000a1', true);
select is((select count(*)::int from realtime.messages), 1, '본인 사용자 알림만 읽는다');
select set_config('realtime.topic', 'user:00000000-0000-0000-0000-0000000000b1', true);
select is((select count(*)::int from realtime.messages), 0, '상대라도 사용자 알림은 읽지 못한다');
select set_config('realtime.topic', 'couple-shares:10000000-0000-0000-0000-000000000001', true);
select is((select count(*)::int from realtime.messages), 2, '현재 커플은 승인 무효화 알림을 읽는다');
select throws_ok($$insert into realtime.messages(id, topic, extension, payload, event, private)
 values(gen_random_uuid(), 'couple:10000000-0000-0000-0000-000000000001', 'broadcast', '{}', 'photos', true)$$,
 '42501', 'new row violates row-level security policy for table "messages"', '클라이언트가 임의 알림을 발신하지 못한다');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select set_config('realtime.topic', 'couple:10000000-0000-0000-0000-000000000001', true);
select is((select count(*)::int from realtime.messages), 0, '다른 커플 멤버는 같은 topic을 알아도 읽지 못한다');
set local role anon;
select is((select count(*)::int from realtime.messages), 0, '비로그인 계정은 읽지 못한다');
reset role;
update couples set status = 'archived' where id = '10000000-0000-0000-0000-000000000001';
update users set active_couple_id = null where id in
 ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select set_config('realtime.topic', 'couple:10000000-0000-0000-0000-000000000001', true);
select is((select count(*)::int from realtime.messages), 2, '아카이브 멤버의 영구 읽기 권한을 유지한다');
select set_config('realtime.topic', 'couple-shares:10000000-0000-0000-0000-000000000001', true);
select is((select count(*)::int from realtime.messages), 0, '아카이브 후 승인 알림 신규 가입은 거부한다');
reset role;
select * from finish();
rollback;
