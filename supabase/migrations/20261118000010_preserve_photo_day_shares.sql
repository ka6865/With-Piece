-- 자동 스캔은 현재 커플에서 승인한 원본을 보존한다. 전체 교체 API는 그대로 둔다.
create function public.sync_photo_days(p_couple_id uuid, p_rows jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := auth.uid();
  started date;
begin
  if me is null or p_couple_id is null then raise exception 'no_active_couple'; end if;
  perform pg_advisory_xact_lock(
    hashtextextended('photo_day_shares:' || me::text || ':' || p_couple_id::text, 0)
  );
  if private.my_couple_id() is distinct from p_couple_id then raise exception 'no_active_couple'; end if;
  select c.started_on into started from public.couples c where c.id = p_couple_id;
  if started is null or p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'invalid_photo_days';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_rows) r(day date, region_id text, photo_count int)
    where r.day is null or r.region_id is null or r.photo_count is null or r.photo_count <= 0
  ) then raise exception 'invalid_photo_days'; end if;
  delete from public.photo_days d where d.user_id = me and (
    d.day < started or (
      not exists (select 1 from jsonb_to_recordset(p_rows) r(day date, region_id text)
        where r.day = d.day and r.region_id = d.region_id)
      and not exists (select 1 from public.photo_day_shares s
        where s.user_id = me and s.couple_id = p_couple_id and s.day = d.day and s.region_id = d.region_id)
    )
  );
  insert into public.photo_days(user_id, day, region_id, photo_count)
    select me, r.day, r.region_id, r.photo_count
    from jsonb_to_recordset(p_rows) r(day date, region_id text, photo_count int)
    where r.day >= started
    on conflict (user_id, day, region_id) do update set photo_count = excluded.photo_count;
end $$;

-- 화면을 연 뒤 다른 기기에서 추가한 승인은 보존하고 명시적 변경만 반영한다.
create function public.update_photo_day_shares(p_couple_id uuid, p_approve jsonb, p_revoke jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := auth.uid();
  started date;
begin
  if me is null or p_couple_id is null then raise exception 'no_active_couple'; end if;
  perform pg_advisory_xact_lock(
    hashtextextended('photo_day_shares:' || me::text || ':' || p_couple_id::text, 0)
  );
  if private.my_couple_id() is distinct from p_couple_id then raise exception 'no_active_couple'; end if;
  select c.started_on into started from public.couples c where c.id = p_couple_id;
  if started is null or p_approve is null or p_revoke is null
    or jsonb_typeof(p_approve) <> 'array' or jsonb_typeof(p_revoke) <> 'array' then
    raise exception 'invalid_share';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_approve) r(day date, region_id text)
    where r.day is null or r.region_id is null or r.day < started
      or not exists (select 1 from public.photo_days d
        where d.user_id = me and d.day = r.day and d.region_id = r.region_id)
      or exists (select 1 from jsonb_to_recordset(p_revoke) x(day date, region_id text)
        where x.day = r.day and x.region_id = r.region_id)
  ) or exists (
    select 1 from jsonb_to_recordset(p_revoke) r(day date, region_id text)
    where r.day is null or r.region_id is null
  ) then raise exception 'invalid_share'; end if;
  delete from public.photo_day_shares s where s.user_id = me and s.couple_id = p_couple_id
    and (s.day < started or exists (
      select 1 from jsonb_to_recordset(p_revoke) r(day date, region_id text)
      where r.day = s.day and r.region_id = s.region_id
    ));
  insert into public.photo_day_shares(couple_id, user_id, day, region_id)
    select distinct p_couple_id, me, r.day, r.region_id
    from jsonb_to_recordset(p_approve) r(day date, region_id text)
    on conflict do nothing;
end $$;
revoke execute on function public.sync_photo_days(uuid, jsonb) from public, anon;
revoke execute on function public.update_photo_day_shares(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.sync_photo_days(uuid, jsonb) to authenticated;
grant execute on function public.update_photo_day_shares(uuid, jsonb, jsonb) to authenticated;
