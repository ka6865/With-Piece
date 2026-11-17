-- 전체 교체 RPC는 승인 보존과 잠금을 우회하므로 없앤다. 구버전 앱의 호출은 실패한다.
drop function public.replace_photo_days(jsonb);
drop function public.replace_photo_day_shares(uuid, jsonb);

-- 승인 항목은 장수를 함께 받아 원본을 맞춘다. 다른 기기의 동기화가 지운 날짜도
-- 이 기기 스냅샷으로 승인할 수 있다.
create or replace function public.update_photo_day_shares(p_couple_id uuid, p_approve jsonb, p_revoke jsonb) returns void
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
    select 1 from jsonb_to_recordset(p_approve) r(day date, region_id text, photo_count int)
    where r.day is null or r.region_id is null or r.day < started
      or r.photo_count is null or r.photo_count <= 0
      or exists (select 1 from jsonb_to_recordset(p_revoke) x(day date, region_id text)
        where x.day = r.day and x.region_id = r.region_id)
  ) or exists (
    select 1 from jsonb_to_recordset(p_revoke) r(day date, region_id text)
    where r.day is null or r.region_id is null
  ) then raise exception 'invalid_share'; end if;
  insert into public.photo_days(user_id, day, region_id, photo_count)
    select me, r.day, r.region_id, max(r.photo_count)
    from jsonb_to_recordset(p_approve) r(day date, region_id text, photo_count int)
    group by r.day, r.region_id
    on conflict (user_id, day, region_id) do update set photo_count = excluded.photo_count;
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
