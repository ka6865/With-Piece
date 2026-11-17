-- 여행 확인·버림(설계 5.4). 여행과 조각을 한 트랜잭션으로 만든다.
-- security invoker라 RLS(couple_id = my_couple_id())가 그대로 적용된다

-- 두 사람이 같은 후보를 동시에 확인하거나, 버린 후보를 다시 확인해도 하나만 남는다.
-- 수동 여행은 기간이 겹쳐도 된다
create unique index trips_auto_once on public.trips (couple_id, started_on, ended_on)
  where source = 'auto';

create function public.confirm_trip(
  p_title text,
  p_started_on date,
  p_ended_on date,
  p_region_ids text[],
  p_source text
) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  couple uuid := private.my_couple_id();
  trip uuid;
begin
  if couple is null then
    raise exception 'no_active_couple';
  end if;
  if coalesce(cardinality(p_region_ids), 0) = 0 then
    raise exception 'empty_regions';
  end if;
  insert into public.trips (couple_id, title, started_on, ended_on, status, source, created_by)
    values (couple, p_title, p_started_on, p_ended_on, 'confirmed', p_source, auth.uid())
    returning id into trip;
  insert into public.trip_regions (trip_id, couple_id, region_id)
    select trip, couple, region from (select distinct unnest(p_region_ids) as region) r;
  return trip;
end $$;

create function public.dismiss_trip(p_started_on date, p_ended_on date) returns uuid
language plpgsql security invoker set search_path = '' as $$
declare
  couple uuid := private.my_couple_id();
  trip uuid;
begin
  if couple is null then
    raise exception 'no_active_couple';
  end if;
  insert into public.trips (couple_id, title, started_on, ended_on, status, source, created_by)
    values (couple, '', p_started_on, p_ended_on, 'dismissed', 'auto', auth.uid())
    returning id into trip;
  return trip;
end $$;

revoke execute on function public.confirm_trip(text, date, date, text[], text) from public, anon;
revoke execute on function public.dismiss_trip(date, date) from public, anon;
grant execute on function public.confirm_trip(text, date, date, text[], text) to authenticated;
grant execute on function public.dismiss_trip(date, date) to authenticated;
