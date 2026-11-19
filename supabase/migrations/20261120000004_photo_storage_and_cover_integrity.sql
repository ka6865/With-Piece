-- 이미 기록된 경로는 읽을 수 있게 두고 새 사진 경로가 해당 커플과 여행에 속하게 한다.
alter table public.photos add constraint photos_object_key_scope check (
  object_key ~ ('^' || couple_id::text || '/' || trip_id::text || '/[A-Za-z0-9_-]+[.](heic|jpg|jpeg)$')
) not valid;

-- 경로에 값을 캐스트하지 않아 잘못된 입력도 안전하게 거부한다.
drop policy photos_bucket_select on storage.objects;
create policy photos_bucket_select on storage.objects
  for select to authenticated using (
    bucket_id = 'photos'
    and split_part(name, '/', 1) in (select id::text from private.my_couple_ids() as id)
  );

drop policy photos_bucket_insert on storage.objects;
create policy photos_bucket_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'photos'
    and split_part(name, '/', 1) = (select private.my_couple_id())::text
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/(full|thumb)/[A-Za-z0-9_-]+[.](heic|jpg|jpeg)$'
    and exists (
      select 1 from public.trips t
      where t.couple_id = (select private.my_couple_id())
        and t.id = case
          when split_part(name, '/', 2) ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
          then split_part(name, '/', 2)::uuid
        end
    )
  );

drop policy photos_bucket_delete on storage.objects;
create policy photos_bucket_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'photos'
    and split_part(name, '/', 1) = (select private.my_couple_id())::text
    and owner = (select auth.uid())
  );

update storage.buckets
set file_size_limit = 10485760, allowed_mime_types = array['image/heic', 'image/jpeg']
where id = 'photos';

-- 사진 행 등록에 실패한 파일도 대상 커플의 저장소 경로에서 찾는다.
create or replace function public.purge_expired_users()
returns table (user_id uuid, object_paths text[])
language plpgsql security definer set search_path = '' as $$
declare
  expired uuid;
begin
  for expired in
    select u.id from public.users u
    where u.deletion_requested_at <= now() - interval '30 days'
    order by u.deletion_requested_at, u.id limit 50 for update skip locked
  loop
    update public.users set deletion_started_at = coalesce(deletion_started_at, now())
      where id = expired;
    user_id := expired;
    select coalesce(array_agg(o.name order by o.name), '{}')
      into object_paths
      from public.couples c
      join storage.objects o on o.bucket_id = 'photos' and o.name like c.id::text || '/%'
      where expired in (c.user_a_id, c.user_b_id)
        and o.name ~ '^[0-9a-f-]{36}/[A-Za-z0-9_-]+/(full|thumb)/[A-Za-z0-9_-]+[.](heic|jpg|jpeg)$';
    return next;
  end loop;
end $$;

create or replace function public.orphan_photo_paths() returns setof text
language sql stable security definer set search_path = '' as $$
  select o.name from storage.objects o
  where o.bucket_id = 'photos'
    and o.created_at < now() - interval '24 hours'
    and not exists (
      select 1 from public.photos p
      where p.object_key = regexp_replace(o.name, '/(full|thumb)/', '/')
        and p.couple_id::text = split_part(o.name, '/', 1)
        and p.trip_id::text = split_part(o.name, '/', 2)
    )
  order by o.created_at, o.name
  limit 500;
$$;

-- 기존 작성자 참조가 사용자의 최종 탈퇴를 막지 않게 한다.
alter table public.trips
  drop constraint trips_created_by_fkey,
  add constraint trips_created_by_fkey foreign key (created_by)
    references public.users(id) on delete set null;
alter table public.couple_region_overrides
  drop constraint couple_region_overrides_updated_by_fkey,
  add constraint couple_region_overrides_updated_by_fkey foreign key (updated_by)
    references public.users(id) on delete set null;

create function private.set_trip_author() returns trigger
language plpgsql set search_path = '' as $$
begin
  if auth.uid() is not null and current_user = 'authenticated' then
    new.created_by := case when tg_op = 'INSERT' then auth.uid() else old.created_by end;
  end if;
  return new;
end $$;
revoke all on function private.set_trip_author() from public, anon, authenticated;
create trigger set_trip_author before insert or update on public.trips
  for each row execute function private.set_trip_author();

create function private.set_override_author() returns trigger
language plpgsql set search_path = '' as $$
begin
  if auth.uid() is not null and current_user = 'authenticated' then
    new.updated_by := auth.uid();
    new.updated_at := now();
  end if;
  return new;
end $$;
revoke all on function private.set_override_author() from public, anon, authenticated;
create trigger set_override_author before insert or update on public.couple_region_overrides
  for each row execute function private.set_override_author();

alter function private.cover_photo_matches(uuid, text) security invoker;

delete from public.region_covers c using public.photos p
where p.id = c.photo_id and p.couple_id = c.couple_id
  and p.region_id is distinct from c.region_id
  and not exists (
    select 1 from public.trip_regions tr
    where tr.trip_id = p.trip_id and tr.couple_id = c.couple_id and tr.region_id = c.region_id
  );


-- 촬영 조각이 다르면 여행에 대상 조각이 남아 있을 때만 대표 자격을 유지한다.
create function private.clear_detached_region_cover() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' and (new.trip_id, new.region_id) = (old.trip_id, old.region_id) then
    return null;
  end if;
  delete from public.region_covers c
  using public.photos p
  where c.couple_id = old.couple_id and c.region_id = old.region_id
    and c.photo_id = p.id and c.couple_id = p.couple_id
    and p.trip_id = old.trip_id and p.region_id is distinct from old.region_id;
  return null;
end $$;
revoke all on function private.clear_detached_region_cover() from public, anon, authenticated;
create trigger clear_detached_region_cover after delete or update of trip_id, region_id
  on public.trip_regions for each row execute function private.clear_detached_region_cover();

create index couples_user_a_idx on public.couples (user_a_id);
create index couples_user_b_idx on public.couples (user_b_id);
create index photos_couple_taken_idx on public.photos (couple_id, taken_at, id);
create index region_covers_photo_idx on public.region_covers (photo_id, couple_id);

-- 내용 전체를 받지 않고 여행별 상대 댓글의 최신 시각만 읽는다.
create function public.partner_latest_comments(p_couple_id uuid)
returns table (trip_id uuid, latest_at timestamptz)
language sql stable security invoker set search_path = '' as $$
  select c.trip_id, max(c.created_at)
  from (
    select g.trip_id, g.created_at from public.guestbook_entries g
    where g.couple_id = p_couple_id and g.author_id <> (select auth.uid())
    union all
    select p.trip_id, pc.created_at from public.photo_comments pc
    join public.photos p on p.id = pc.photo_id and p.couple_id = pc.couple_id
    where pc.couple_id = p_couple_id and pc.author_id <> (select auth.uid())
  ) c
  group by c.trip_id
  order by c.trip_id;
$$;
revoke all on function public.partner_latest_comments(uuid) from public, anon;
grant execute on function public.partner_latest_comments(uuid) to authenticated;

-- 이전 관계의 삭제 요청과 취소도 상대에게 행 정보 없이 갱신 신호만 보낸다.
create function private.notify_archive_deletion_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_table_name = 'couples' then
    perform realtime.send('{}'::jsonb, 'archive', 'user:' || old.user_a_id::text, true);
    perform realtime.send('{}'::jsonb, 'archive', 'user:' || old.user_b_id::text, true);
  elsif new.deletion_requested_at is distinct from old.deletion_requested_at then
    perform realtime.send('{}'::jsonb, 'archive', 'user:' || member.id::text, true)
    from (
      select new.id as id
      union
      select case when c.user_a_id = new.id then c.user_b_id else c.user_a_id end
      from public.couples c where new.id in (c.user_a_id, c.user_b_id)
    ) member;
  end if;
  return null;
end $$;
revoke all on function private.notify_archive_deletion_change() from public, anon, authenticated;
create trigger notify_archive_request after update of deletion_requested_at on public.users
  for each row execute function private.notify_archive_deletion_change();
create trigger notify_archive_removed after delete on public.couples
  for each row execute function private.notify_archive_deletion_change();
