-- 비교 승인은 현재 커플과 본인에게만 속한다. 비승인 원본은 교집합에 쓰지 않는다.
create table public.photo_day_shares (
  couple_id uuid not null references public.couples(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  day date not null,
  region_id text not null,
  primary key (couple_id, user_id, day, region_id),
  foreign key (user_id, day, region_id)
    references public.photo_days(user_id, day, region_id) on delete cascade
);
alter table public.photo_day_shares enable row level security;
grant select, insert, delete on public.photo_day_shares to authenticated;
revoke update on public.photo_day_shares from anon, authenticated;
create policy photo_day_shares_select on public.photo_day_shares
  for select to authenticated using (user_id = (select auth.uid()));
create policy photo_day_shares_insert on public.photo_day_shares
  for insert to authenticated with check (
    user_id = (select auth.uid())
    and couple_id = (select private.my_couple_id())
    and day >= (select c.started_on from public.couples c where c.id = photo_day_shares.couple_id)
  );
create policy photo_day_shares_delete on public.photo_day_shares
  for delete to authenticated using (
    user_id = (select auth.uid()) and couple_id = (select private.my_couple_id())
  );

create function public.replace_photo_day_shares(p_couple_id uuid, p_rows jsonb) returns void
language plpgsql security invoker set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid := private.my_couple_id();
  started date;
begin
  if couple is null or couple is distinct from p_couple_id then raise exception 'no_active_couple'; end if;
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
revoke execute on function public.replace_photo_day_shares(uuid, jsonb) from public, anon;
grant execute on function public.replace_photo_day_shares(uuid, jsonb) to authenticated;

create or replace function public.couple_matched_days()
returns table (day date, region_id text)
language sql stable security definer set search_path = '' as $$
  select a.day, a.region_id
  from public.couples c
  join public.photo_day_shares a on a.couple_id = c.id and a.user_id = c.user_a_id
  join public.photo_day_shares b on b.couple_id = c.id and b.user_id = c.user_b_id
    and b.day = a.day and b.region_id = a.region_id
  where c.id = private.my_couple_id() and c.started_on is not null
    and a.day >= c.started_on
  order by a.day, a.region_id;
$$;
