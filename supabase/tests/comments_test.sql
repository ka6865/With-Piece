begin;
select plan(28);

-- a·b 커플, c는 다른 커플. 여행 하나와 사진 하나
insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000d1');
insert into couples (id, user_a_id, user_b_id) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1');
update users set active_couple_id = '10000000-0000-0000-0000-000000000001'
  where id in ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000b1');
update users set active_couple_id = '10000000-0000-0000-0000-000000000002'
  where id in ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1');
insert into trips (id, couple_id, title, started_on, ended_on, status, source) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '속초', '2026-10-03', '2026-10-03', 'confirmed', 'manual'),
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '경주', '2026-10-03', '2026-10-03', 'confirmed', 'manual');
insert into photos (id, trip_id, couple_id, object_key, width, height, byte_size, uploaded_by) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001',
   '10000000-0000-0000-0000-000000000001/30000000-0000-0000-0000-000000000001/a.heic', 1, 1, 1,
   '00000000-0000-0000-0000-0000000000a1');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);

select lives_ok($$ insert into guestbook_entries (trip_id, couple_id, content)
  values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '또 가자') $$,
  '내 커플 여행에 방명록을 쓴다');
select lives_ok($$ insert into photo_comments (photo_id, couple_id, content)
  values ('40000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '이 사진 좋다') $$,
  '내 커플 사진에 댓글을 쓴다');
select is((select author_id from guestbook_entries), '00000000-0000-0000-0000-0000000000a1'::uuid, '작성자는 서버가 정한다');
select throws_ok($$ insert into guestbook_entries (trip_id, couple_id, author_id, content)
  values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1', '사칭') $$,
  '42501', null, '작성자를 직접 지정하지 못한다');
select throws_ok($$ insert into guestbook_entries (trip_id, couple_id, content)
  values ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', '남의 여행') $$,
  '42501', null, '다른 커플 여행에 쓰지 못한다');
select throws_ok($$ insert into guestbook_entries (trip_id, couple_id, content)
  values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', repeat('가', 201)) $$,
  '23514', null, '200자를 넘으면 거부한다');
select throws_ok($$ insert into guestbook_entries (trip_id, couple_id, content)
  values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '') $$,
  '23514', null, '빈 글은 거부한다');

update guestbook_entries set content = '또 가자!!';
select ok((select updated_at is not null and content = '또 가자!!' from guestbook_entries), '본인 글을 고치면 수정 시각이 남는다');
select throws_ok($$ update guestbook_entries set created_at = now() - interval '1 day' $$,
  '42501', null, '본문 외 칸은 고치지 못한다');

-- 상대(b)는 읽을 수 있지만 고치거나 지우지 못한다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b1","role":"authenticated"}', true);
select is((select count(*)::int from guestbook_entries), 1, '상대 방명록을 읽는다');
update guestbook_entries set content = '바꿈';
delete from photo_comments;
select is((select content from guestbook_entries), '또 가자!!', '상대 글을 고치지 못한다');
select is((select count(*)::int from photo_comments), 1, '상대 댓글을 지우지 못한다');

select lives_ok($$ select submit_content_report('photo', '40000000-0000-0000-0000-000000000001', 'privacy') $$,
  '커플 사진을 신고할 수 있다');
select lives_ok($$ select submit_content_report('photo', '40000000-0000-0000-0000-000000000001', 'privacy') $$,
  '같은 신고를 재시도할 수 있다');
select lives_ok($$ select submit_content_report('photo_comment', (select id from photo_comments), 'other') $$,
  '사진 댓글을 신고할 수 있다');
select throws_ok($$ select submit_content_report('photo', '40000000-0000-0000-0000-000000000001', 'invalid') $$,
  '22023', 'invalid report reason', '정의된 사유만 받는다');
select throws_ok($$ select * from content_reports $$,
  '42501', null, '앱에서 운영자용 신고 목록을 열 수 없다');

-- 다른 커플(c)은 읽지 못한다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c1","role":"authenticated"}', true);
select is((select count(*)::int from guestbook_entries) + (select count(*)::int from photo_comments), 0, '다른 커플은 댓글을 읽지 못한다');

select throws_ok($$ select submit_content_report('photo', '40000000-0000-0000-0000-000000000001', 'privacy') $$,
  '42501', 'target unavailable', '다른 커플의 사진은 신고할 수 없다');

-- 아카이브하면 읽기만 된다
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select archive_couple();
select is((select count(*)::int from guestbook_entries), 1, '지난 커플의 방명록을 읽는다');
select throws_ok($$ insert into guestbook_entries (trip_id, couple_id, content)
  values ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '이제 못 씀') $$,
  '42501', null, '지난 커플에는 쓰지 못한다');

select lives_ok($$ select submit_content_report('trip_comment', (select id from guestbook_entries), 'harassment') $$,
  '지난 여행 방명록도 신고할 수 있다');

reset role;
set local role anon;
select throws_ok($$ select submit_content_report('photo', '40000000-0000-0000-0000-000000000001', 'privacy') $$,
  '42501', null, '비로그인 호출은 거부한다');
reset role;
set local role service_role;
select is((select count(*)::int from content_reports), 3, '운영자가 중복을 제외한 신고를 읽는다');
select is((select reason from content_reports where target_kind = 'photo'), 'privacy', '사진 신고 사유를 보관한다');

-- 사진을 지우면 댓글도 지워진다
reset role;
delete from photos where id = '40000000-0000-0000-0000-000000000001';
select is((select count(*)::int from photo_comments), 0, '사진 삭제는 댓글을 함께 지운다');
select ok((select relrowsecurity from pg_class where oid = 'public.guestbook_entries'::regclass)
  and (select relrowsecurity from pg_class where oid = 'public.photo_comments'::regclass), '두 댓글 테이블 RLS 활성화');

select ok(has_table_privilege('authenticated', 'public.guestbook_entries', 'SELECT, DELETE')
  and has_table_privilege('authenticated', 'public.photo_comments', 'SELECT, DELETE'),
  '자동 권한 부여 없이도 조회·삭제 권한이 있다');
select * from finish();
rollback;
