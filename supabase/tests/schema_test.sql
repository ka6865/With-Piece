begin;
select plan(13);

select has_table('public', 'photo_days', 'photo_days가 있다');
select col_not_null('public', 'couples', 'user_b_id', '커플은 두 사람이 확정된 상태만 담는다');
select is((select count(*)::int from regions), 246, 'regions는 시도 17 + 조각 229');
select is((select count(*)::int from regions where depth = 2), 229, '조각 229개');

select throws_ok($$ insert into couples (user_a_id, user_b_id) values
  ('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001') $$,
  '23514', null, '자기 자신과 커플 불가');
select throws_ok($$ insert into photo_days values
  ('00000000-0000-0000-0000-000000000001', '2026-01-01', '32060', 0) $$,
  '23514', null, 'photo_count는 양수');
select throws_ok($$ insert into trips (couple_id, title, started_on, ended_on, status, source)
  values (gen_random_uuid(), 't', '2026-01-02', '2026-01-01', 'confirmed', 'auto') $$,
  '23514', null, '종료일은 시작일 이후');
select throws_ok($$ insert into couple_invites (inviter_id, code, expires_at, accepted_at)
  values (gen_random_uuid(), 'x', now(), now()) $$,
  '23514', null, '수락 시각과 수락자는 함께 채운다');

select has_index('public', 'couple_invites', 'couple_invites_one_open', '미수락 초대 하나');
select has_view('public', 'couple_visited_regions', '진행률 view');
select ok((select 'security_invoker=true' = any(reloptions) from pg_class
  where relname = 'couple_visited_regions'), 'view는 조회자 권한으로 실행');
select is((select public from storage.buckets where id = 'photos'), false, '사진 버킷은 비공개');

-- 가입하면 public.users 행이 생긴다
insert into auth.users (id, raw_user_meta_data)
  values ('00000000-0000-0000-0000-00000000000a', '{"name": "가"}');
select is((select nickname from users where id = '00000000-0000-0000-0000-00000000000a'),
  '가', '가입 트리거가 users 행을 만든다');

select * from finish();
rollback;
