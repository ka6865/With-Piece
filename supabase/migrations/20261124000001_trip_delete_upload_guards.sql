-- 삭제 확인 시점의 사진 수와 업로드 시점의 여행 상태를 DB에서 직렬화한다.
create or replace function public.delete_trip(
  p_trip_id uuid,
  p_expected_photo_count integer
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  couple uuid := private.my_couple_id();
  t public.trips;
  actual_photo_count integer;
begin
  select * into t from public.trips
    where id = p_trip_id and couple_id = couple and status = 'confirmed'
    for update;
  if couple is null or not found then
    raise exception 'trip_not_found';
  end if;

  -- 사진 개별 삭제가 표지 참조를 정리 중이면 잠금을 기다리지 않고 다시 시도하게 한다.
  perform 1 from public.photos p where p.trip_id = t.id for update nowait;
  select count(*)::integer into actual_photo_count
    from public.photos where trip_id = t.id;
  if actual_photo_count is distinct from p_expected_photo_count then
    raise exception 'photo_count_changed';
  end if;

  if t.source = 'manual' then
    delete from public.trips where id = t.id;
    return;
  end if;
  update public.trips set cover_photo_id = null where id = t.id;
  delete from public.photos where trip_id = t.id;
  delete from public.trip_regions where trip_id = t.id;
  delete from public.guestbook_entries where trip_id = t.id;
  update public.trips set status = 'dismissed', title = '' where id = t.id;
end $$;

revoke execute on function public.delete_trip(uuid, integer) from public, anon;
grant execute on function public.delete_trip(uuid, integer) to authenticated;

-- 구버전 앱은 확인한 사진 수를 보낼 수 없으므로 파괴 작업을 명시적으로 거부한다.
create or replace function public.delete_trip(p_trip_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'app_update_required';
end $$;
revoke execute on function public.delete_trip(uuid) from public, anon;
grant execute on function public.delete_trip(uuid) to authenticated;

create function private.validate_photo_trip() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  trip_status text;
begin
  if auth.uid() is null then
    return new;
  end if;

  perform 1 from public.trips t
    where t.id = new.trip_id
      and t.couple_id = new.couple_id
      and t.couple_id = private.my_couple_id()
    for share;
  if not found then
    raise exception 'trip_not_uploadable';
  end if;

  select t.status into trip_status from public.trips t where t.id = new.trip_id;
  if trip_status <> 'confirmed' then
    raise exception 'trip_not_uploadable';
  end if;
  return new;
end $$;
revoke all on function private.validate_photo_trip() from public, anon, authenticated;

create trigger a_validate_photo_trip
before insert on public.photos
for each row execute function private.validate_photo_trip();

drop policy photos_bucket_insert on storage.objects;
create policy photos_bucket_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'photos'
    and split_part(name, '/', 1) = (select private.my_couple_id())::text
    and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/(full|thumb)/[A-Za-z0-9_-]+[.](heic|jpg|jpeg)$'
    and exists (
      select 1 from public.trips t
      where t.couple_id = (select private.my_couple_id())
        and t.status = 'confirmed'
        and t.id = case
          when split_part(name, '/', 2) ~ '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
          then split_part(name, '/', 2)::uuid
        end
    )
  );
