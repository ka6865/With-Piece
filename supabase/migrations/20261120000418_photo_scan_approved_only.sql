-- 승인 원본을 찾거나 철회된 행의 참조를 판단하는 인덱스다.
create index photo_day_shares_source_idx
  on public.photo_day_shares (user_id, day, region_id);

create or replace function public.sync_photo_days(p_couple_id uuid, p_rows jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  started date;
begin
  if me is null or p_couple_id is null then raise exception 'no_active_couple'; end if;
  select c.started_on into started
  from public.couples c
  join public.users a on a.id = c.user_a_id and a.active_couple_id = c.id
  join public.users b on b.id = c.user_b_id and b.active_couple_id = c.id
  where c.id = p_couple_id and c.status = 'active' and me in (c.user_a_id, c.user_b_id);
  if not found then raise exception 'no_active_couple'; end if;
  if started is null or p_rows is null or jsonb_typeof(p_rows) <> 'array' then
    raise exception 'invalid_photo_days';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_rows) r(day date, region_id text, photo_count int)
    where r.day is null or r.region_id is null or r.photo_count is null or r.photo_count <= 0
  ) then raise exception 'invalid_photo_days'; end if;
  -- 구버전 앱은 호출을 완료하지만 기기 스캔을 서버에 저장하지 않는다.
end $$;
revoke all on function public.sync_photo_days(uuid, jsonb) from public, anon;
grant execute on function public.sync_photo_days(uuid, jsonb) to authenticated;

-- 철회와 커플 삭제 모두 마지막 승인 참조가 없으면 원본을 정리한다.
create function private.prune_unreferenced_photo_days() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.photo_days d
  using removed_shares removed
  where d.user_id = removed.user_id and d.day = removed.day and d.region_id = removed.region_id
    and not exists (
      select 1 from public.photo_day_shares s
      where s.user_id = d.user_id and s.day = d.day and s.region_id = d.region_id
    );
  return null;
end $$;
revoke all on function private.prune_unreferenced_photo_days() from public, anon, authenticated;

create trigger prune_unreferenced_photo_days
  after delete on public.photo_day_shares
  referencing old table as removed_shares for each statement
  execute function private.prune_unreferenced_photo_days();

-- 어느 관계에서도 승인하지 않은 예전 서버 집계만 정리한다.
delete from public.photo_days d
where not exists (
  select 1 from public.photo_day_shares s
  where s.user_id = d.user_id and s.day = d.day and s.region_id = d.region_id
);
