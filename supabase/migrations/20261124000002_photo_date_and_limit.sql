create table private.photo_quota_defaults (
  singleton boolean primary key default true check (singleton),
  photo_limit integer not null check (photo_limit >= 0)
);
insert into private.photo_quota_defaults (photo_limit) values (1000);
alter table private.photo_quota_defaults enable row level security;
revoke all on private.photo_quota_defaults from public, anon, authenticated;

create table private.couple_photo_quota_overrides (
  couple_id uuid primary key references public.couples(id) on delete cascade,
  photo_limit integer not null check (photo_limit >= 0)
);
alter table private.couple_photo_quota_overrides enable row level security;
revoke all on private.couple_photo_quota_overrides from public, anon, authenticated;

create function public.photo_upload_limit(p_couple_id uuid) returns integer
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_couple_id is null or p_couple_id is distinct from private.my_couple_id() then
    raise exception 'no_active_couple';
  end if;
  return coalesce(
    (select o.photo_limit from private.couple_photo_quota_overrides o where o.couple_id = p_couple_id),
    (select d.photo_limit from private.photo_quota_defaults d where d.singleton)
  );
end $$;
revoke execute on function public.photo_upload_limit(uuid) from public, anon;
grant execute on function public.photo_upload_limit(uuid) to authenticated;

create function public.photo_usage(p_couple_id uuid)
returns table (photo_count bigint, photo_limit integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  if p_couple_id is null or p_couple_id is distinct from private.my_couple_id() then
    raise exception 'no_active_couple';
  end if;
  return query select count(*)::bigint, public.photo_upload_limit(p_couple_id)
    from public.photos p where p.couple_id = p_couple_id;
end $$;
revoke execute on function public.photo_usage(uuid) from public, anon;
grant execute on function public.photo_usage(uuid) to authenticated;

create function private.check_photo_date_and_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  start_date date;
  limit_count integer;
begin
  -- 앞선 여행 트리거가 잠근 여행 행을 다시 잠그지 않는다.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.couple_id::text, 713));
  if exists (select 1 from public.photos p where p.id = new.id
             and p.couple_id = new.couple_id and p.trip_id = new.trip_id) then
    return new;
  end if;
  select c.started_on into start_date from public.couples c where c.id = new.couple_id;
  if new.taken_at is not null and start_date is not null
     and (new.taken_at at time zone 'Asia/Seoul')::date < start_date then
    raise exception using errcode = 'P0001', message = 'photo_before_started_on';
  end if;
  select coalesce(o.photo_limit, d.photo_limit) into limit_count
    from private.photo_quota_defaults d
    left join private.couple_photo_quota_overrides o on o.couple_id = new.couple_id
    where d.singleton;
  if limit_count is null then
    raise exception using errcode = 'P0001', message = 'photo_limit_unconfigured';
  end if;
  if (select count(*) from public.photos p where p.couple_id = new.couple_id) >= limit_count then
    raise exception using errcode = 'P0001', message = 'photo_limit_exceeded';
  end if;
  return new;
end $$;
revoke all on function private.check_photo_date_and_limit() from public, anon, authenticated;

-- 이름순 실행으로 여행 삭제의 행 잠금 트리거 뒤에 실행한다.
create trigger zzzz_photo_date_and_limit
before insert on public.photos
for each row execute function private.check_photo_date_and_limit();
