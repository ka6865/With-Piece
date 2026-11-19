-- 관계 변경과 스캔·승인의 잠금 순서를 통일하고 앱에 필요한 관계 정보만 반환한다.

create or replace function private.lock_couple_users(p_couple_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform 1
  from public.users u
  where u.id in (
    select member.id from public.couples c
    cross join lateral (values (c.user_a_id), (c.user_b_id)) as member(id)
    where c.id = p_couple_id and (select auth.uid()) in (c.user_a_id, c.user_b_id)
  )
  order by u.id
  for update;
end $$;
revoke all on function private.lock_couple_users(uuid) from public, anon, authenticated;

-- users 직접 조회는 소유자 행으로 한정한다. 상대 프로필은 아래 RPC의 반환 열만 공개한다.
drop policy users_select on public.users;
create policy users_select on public.users
  for select to authenticated using (id = (select auth.uid()));

create function public.current_couple()
returns table (
  couple_id uuid,
  partner_id uuid,
  started_on date,
  my_name text,
  partner_name text,
  my_home_region_id text
)
language sql stable security definer set search_path = '' as $$
  select c.id,
         case when c.user_a_id = auth.uid() then c.user_b_id else c.user_a_id end,
         c.started_on,
         mine.nickname,
         partner.nickname,
         mine.home_region_id
  from public.users mine
  join public.couples c on c.id = mine.active_couple_id and c.status = 'active'
  join public.users partner
    on partner.id = case when c.user_a_id = mine.id then c.user_b_id else c.user_a_id end
   and partner.active_couple_id = c.id
  where mine.id = auth.uid()
    and auth.uid() in (c.user_a_id, c.user_b_id);
$$;

create function public.archived_couples()
returns table (
  couple_id uuid,
  partner_name text,
  archived_at timestamptz,
  partner_deletion_requested_at timestamptz
)
language sql stable security definer set search_path = '' as $$
  select c.id, partner.nickname, c.archived_at, partner.deletion_requested_at
  from public.couples c
  join public.users partner
    on partner.id = case when c.user_a_id = auth.uid() then c.user_b_id else c.user_a_id end
  where c.status = 'archived'
    and auth.uid() in (c.user_a_id, c.user_b_id)
  order by c.archived_at desc;
$$;

revoke all on function public.current_couple() from public, anon;
revoke all on function public.archived_couples() from public, anon;
grant execute on function public.current_couple(), public.archived_couples() to authenticated;

-- 기준일이 바뀌면 두 사람의 이전 승인과 원본을 같은 트랜잭션에서 없앤다.
create or replace function public.set_started_on(p_date date) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid;
  old_started date;
begin
  if p_date is null then raise exception 'invalid_date'; end if;
  if p_date > (now() at time zone 'Asia/Seoul')::date then
    raise exception 'future_date';
  end if;
  select u.active_couple_id into couple from public.users u where u.id = me;
  if me is null or couple is null then raise exception 'no_active_couple'; end if;
  perform private.lock_couple_users(couple);
  select c.started_on into old_started
  from public.couples c
  join public.users a on a.id = c.user_a_id and a.active_couple_id = c.id
  join public.users b on b.id = c.user_b_id and b.active_couple_id = c.id
  where c.id = couple and c.status = 'active' and me in (c.user_a_id, c.user_b_id)
  for update of c;
  if not found then raise exception 'no_active_couple'; end if;
  update public.couples set started_on = p_date where id = couple;
  if old_started is null or p_date > old_started then
    delete from public.photo_day_shares
    where couple_id = couple and day < p_date;
    delete from public.photo_days
    where user_id in (
      select c.user_a_id from public.couples c where c.id = couple
      union
      select c.user_b_id from public.couples c where c.id = couple
    ) and day < p_date;
  end if;
end $$;

-- 거주지와 생활권 지정은 한 RPC 트랜잭션으로 저장한다.
create function public.set_home_region(p_region_id text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid;
begin
  select u.active_couple_id into couple from public.users u where u.id = me;
  if me is null or couple is null then raise exception 'no_active_couple'; end if;
  perform private.lock_couple_users(couple);
  if not exists (
    select 1 from public.couples c
    join public.users a on a.id = c.user_a_id and a.active_couple_id = c.id
    join public.users b on b.id = c.user_b_id and b.active_couple_id = c.id
    where c.id = couple and c.status = 'active' and me in (c.user_a_id, c.user_b_id)
  ) then raise exception 'no_active_couple'; end if;
  update public.users set home_region_id = p_region_id where id = me;
  insert into public.couple_region_overrides
    (couple_id, region_id, kind, updated_by, updated_at)
  values (couple, p_region_id, 'home', me, now())
  on conflict (couple_id, region_id) do update
    set kind = 'home', updated_by = excluded.updated_by, updated_at = excluded.updated_at;
end $$;
revoke all on function public.set_home_region(text) from public, anon;
grant execute on function public.set_home_region(text) to authenticated;

create or replace function public.archive_couple() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid;
begin
  select u.active_couple_id into couple from public.users u where u.id = me;
  if me is null or couple is null then raise exception 'no_active_couple'; end if;
  perform private.lock_couple_users(couple);
  if not exists (
    select 1 from public.couples c
    join public.users a on a.id = c.user_a_id and a.active_couple_id = c.id
    join public.users b on b.id = c.user_b_id and b.active_couple_id = c.id
    where c.id = couple and c.status = 'active' and me in (c.user_a_id, c.user_b_id)
  ) then raise exception 'no_active_couple'; end if;
  update public.couples set status = 'archived', archived_at = now() where id = couple;
  update public.users set active_couple_id = null where active_couple_id = couple;
end $$;
revoke all on function public.archive_couple() from public, anon;
grant execute on function public.archive_couple() to authenticated;

create or replace function public.request_account_deletion() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  initial_couple uuid;
  couple uuid;
  requested_at timestamptz;
  started_at timestamptz;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  select active_couple_id into initial_couple from public.users where id = me;
  if initial_couple is null then
    select active_couple_id, deletion_requested_at, deletion_started_at
      into couple, requested_at, started_at
    from public.users where id = me for update;
  else
    perform private.lock_couple_users(initial_couple);
    select active_couple_id, deletion_requested_at, deletion_started_at
      into couple, requested_at, started_at
    from public.users where id = me;
  end if;
  if couple is distinct from initial_couple then
    raise exception 'relationship_changed';
  end if;
  if requested_at is not null then return; end if;
  if started_at is not null then raise exception 'deletion_started'; end if;
  update public.users set deletion_requested_at = now() where id = me;
  if couple is not null then
    update public.couples set status = 'archived', archived_at = now() where id = couple;
    update public.users set active_couple_id = null where active_couple_id = couple;
  end if;
  delete from public.photo_days where user_id = me;
end $$;

create or replace function public.sync_photo_days(p_couple_id uuid, p_rows jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  started date;
begin
  if me is null or p_couple_id is null then raise exception 'no_active_couple'; end if;
  perform private.lock_couple_users(p_couple_id);
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
  delete from public.photo_days d where d.user_id = me and (
    (d.day >= started and not exists (
      select 1 from jsonb_to_recordset(p_rows) r(day date, region_id text, photo_count int)
      where r.day = d.day and r.region_id = d.region_id
    ))
    or d.day < started
  ) and not exists (
    select 1 from public.photo_day_shares s
    where s.user_id = d.user_id and s.day = d.day and s.region_id = d.region_id
  );
  insert into public.photo_days(user_id, day, region_id, photo_count)
    select me, r.day, r.region_id, r.photo_count
    from jsonb_to_recordset(p_rows) r(day date, region_id text, photo_count int)
    where r.day >= started
    on conflict (user_id, day, region_id) do update set photo_count = excluded.photo_count;
end $$;
revoke all on function public.sync_photo_days(uuid, jsonb) from public, anon;
grant execute on function public.sync_photo_days(uuid, jsonb) to authenticated;

create or replace function public.update_photo_day_shares(
  p_couple_id uuid, p_approve jsonb, p_revoke jsonb
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  started date;
begin
  if me is null or p_couple_id is null then raise exception 'no_active_couple'; end if;
  perform private.lock_couple_users(p_couple_id);
  select c.started_on into started
  from public.couples c
  join public.users a on a.id = c.user_a_id and a.active_couple_id = c.id
  join public.users b on b.id = c.user_b_id and b.active_couple_id = c.id
  where c.id = p_couple_id and c.status = 'active' and me in (c.user_a_id, c.user_b_id);
  if not found then raise exception 'no_active_couple'; end if;
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
    on conflict (user_id, day, region_id) do nothing;
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
revoke all on function public.update_photo_day_shares(uuid, jsonb, jsonb) from public, anon;
grant execute on function public.update_photo_day_shares(uuid, jsonb, jsonb) to authenticated;

-- 요청 카드를 닫은 뒤에도 마지막 발송 시각을 유지한다.
alter table public.couple_refresh_state add column last_requested_at timestamptz;
update public.couple_refresh_state set last_requested_at = requested_at
  where requested_at is not null;

create or replace function public.request_refresh() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid;
  partner uuid;
  changed int;
begin
  select u.active_couple_id into couple from public.users u where u.id = me;
  if me is null or couple is null then raise exception 'no_active_couple'; end if;
  perform private.lock_couple_users(couple);
  select case when c.user_a_id = me then c.user_b_id else c.user_a_id end into partner
  from public.couples c
  join public.users a on a.id = c.user_a_id and a.active_couple_id = c.id
  join public.users b on b.id = c.user_b_id and b.active_couple_id = c.id
  where c.id = couple and c.status = 'active' and me in (c.user_a_id, c.user_b_id);
  if not found then raise exception 'no_active_couple'; end if;
  insert into public.couple_refresh_state
    (couple_id, user_id, requested_at, requested_by, last_requested_at)
    values (couple, partner, now(), me, now())
    on conflict (couple_id, user_id) do update
      set requested_at = excluded.requested_at, requested_by = excluded.requested_by,
          last_requested_at = excluded.last_requested_at
      where coalesce(public.couple_refresh_state.last_requested_at,
                     public.couple_refresh_state.requested_at, '-infinity') <= now() - interval '1 hour';
  get diagnostics changed = row_count;
  if changed = 0 then raise exception 'too_soon'; end if;
end $$;
revoke all on function public.request_refresh() from public, anon;
grant execute on function public.request_refresh() to authenticated;

create or replace function public.mark_refreshed() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid;
begin
  select u.active_couple_id into couple from public.users u where u.id = me;
  if me is null or couple is null then raise exception 'no_active_couple'; end if;
  perform private.lock_couple_users(couple);
  if not exists (
    select 1 from public.couples c
    join public.users a on a.id = c.user_a_id and a.active_couple_id = c.id
    join public.users b on b.id = c.user_b_id and b.active_couple_id = c.id
    where c.id = couple and c.status = 'active' and me in (c.user_a_id, c.user_b_id)
  ) then raise exception 'no_active_couple'; end if;
  insert into public.couple_refresh_state (couple_id, user_id, refreshed_at)
    values (couple, me, now())
    on conflict (couple_id, user_id) do update
      set refreshed_at = excluded.refreshed_at, requested_at = null, requested_by = null;
end $$;
revoke all on function public.mark_refreshed() from public, anon;
grant execute on function public.mark_refreshed() to authenticated;

-- 관계와 기준일이 바뀌는 동안에도 같은 잠금을 거치도록 쓰기는 RPC로만 허용한다.
revoke insert, update, delete on public.photo_days, public.photo_day_shares
  from anon, authenticated;
