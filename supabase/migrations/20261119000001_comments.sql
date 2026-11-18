-- 방명록(여행 댓글)·사진 댓글(설계 6.2, 9장). 2026-11-19 2차에서 출시 전으로 앞당겼다.
-- 여행·사진이 지워지면 함께 지워지고, 계정 삭제는 커플 삭제의 연쇄로 정리된다(14.1)

-- 사진 댓글이 사진과 같은 커플을 가리키도록 복합 외래키를 건다
alter table public.photos add constraint photos_id_couple_key unique (id, couple_id);

create table public.guestbook_entries (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null,
  couple_id uuid not null,
  author_id uuid not null default auth.uid() references public.users (id) on delete cascade,
  content text not null check (char_length(content) between 1 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  foreign key (trip_id, couple_id) references public.trips (id, couple_id) on delete cascade
);
create index guestbook_entries_trip_idx on public.guestbook_entries (trip_id, created_at);

create table public.photo_comments (
  id uuid primary key default gen_random_uuid(),
  photo_id uuid not null,
  couple_id uuid not null,
  author_id uuid not null default auth.uid() references public.users (id) on delete cascade,
  content text not null check (char_length(content) between 1 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz,
  foreign key (photo_id, couple_id) references public.photos (id, couple_id) on delete cascade
);
create index photo_comments_photo_idx on public.photo_comments (photo_id, created_at);

create function private.touch_comment() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;
revoke all on function private.touch_comment() from public, anon, authenticated;

alter table public.guestbook_entries enable row level security;
alter table public.photo_comments enable row level security;

-- 읽기는 아카이브 커플까지, 쓰기는 활성 커플이고 본인이 쓴 글만(9장)
do $$
declare
  t text;
begin
  foreach t in array array['guestbook_entries', 'photo_comments'] loop
    execute format(
      'create policy %1$s_select on public.%1$I for select to authenticated
         using (couple_id in (select private.my_couple_ids()))', t);
    execute format(
      'create policy %1$s_insert on public.%1$I for insert to authenticated
         with check (couple_id = (select private.my_couple_id())
                     and author_id = (select auth.uid()))', t);
    execute format(
      'create policy %1$s_update on public.%1$I for update to authenticated
         using (couple_id = (select private.my_couple_id()) and author_id = (select auth.uid()))
         with check (couple_id = (select private.my_couple_id()) and author_id = (select auth.uid()))', t);
    execute format(
      'create policy %1$s_delete on public.%1$I for delete to authenticated
         using (couple_id = (select private.my_couple_id()) and author_id = (select auth.uid()))', t);
    -- 작성자·시각은 서버가 정한다. 수정은 본문만
    execute format('revoke insert, update on public.%I from anon, authenticated', t);
    execute format('grant update (content) on public.%I to authenticated', t);
    -- 수정하면 updated_at을 채워 "수정됨"을 표시한다
    execute format('create trigger %1$s_touch before update on public.%1$I
      for each row execute function private.touch_comment()', t);
    -- 다른 테이블과 같은 비공개 무효화 알림. 행 내용은 보내지 않는다(마이그레이션 11)
    execute format('create trigger notify_insert after insert on public.%I
      referencing new table as changed_rows for each statement
      execute function private.notify_couple_change(%L, %L, %L)', t, 'comments', 'couple_id', 'couple:');
    execute format('create trigger notify_delete after delete on public.%I
      referencing old table as changed_rows for each statement
      execute function private.notify_couple_change(%L, %L, %L)', t, 'comments', 'couple_id', 'couple:');
    execute format('create trigger notify_update after update on public.%I
      referencing old table as old_rows new table as new_rows for each statement
      execute function private.notify_couple_change(%L, %L, %L)', t, 'comments', 'couple_id', 'couple:');
  end loop;
end $$;

grant insert (trip_id, couple_id, content) on public.guestbook_entries to authenticated;
grant insert (photo_id, couple_id, content) on public.photo_comments to authenticated;
