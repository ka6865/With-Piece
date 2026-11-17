create or replace function public.replace_photo_day_shares(p_couple_id uuid, p_rows jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid;
  started date;
begin
  if p_couple_id is null then raise exception 'no_active_couple'; end if;
  -- 같은 계정의 다음 저장은 앞선 저장이 반영된 뒤 현재 목록을 지운다.
  perform pg_advisory_xact_lock(
    hashtextextended('photo_day_shares:' || me::text || ':' || p_couple_id::text, 0)
  );
  couple := private.my_couple_id();
  if couple is distinct from p_couple_id then raise exception 'no_active_couple'; end if;
  select c.started_on into started from public.couples c where c.id = couple;
  if started is null or p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'invalid_share';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_rows) r(day date, region_id text)
    where r.day is null or r.region_id is null or r.day < started
      or not exists (select 1 from public.photo_days d
        where d.user_id = me and d.day = r.day and d.region_id = r.region_id)
  ) then raise exception 'invalid_share'; end if;
  delete from public.photo_day_shares s where s.user_id = me and s.couple_id = couple;
  insert into public.photo_day_shares(couple_id, user_id, day, region_id)
    select distinct couple, me, r.day, r.region_id
    from jsonb_to_recordset(p_rows) r(day date, region_id text);
end $$;
