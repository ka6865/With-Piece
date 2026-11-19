-- 여행 최신화 상태(조각채우기·최신화·대표사진 설계 4.2). 커플마다 사람별 한 행.
-- 상대에게 보이는 것은 언제 최신화했는지와 받은 요청뿐이고 날짜·지역 내용은 없다
create table public.couple_refresh_state (
  couple_id uuid not null references public.couples (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  -- 비교할 기록 선택을 마지막으로 저장한 시각
  refreshed_at timestamptz,
  -- 이 사람이 받은, 아직 처리하지 않은 최신화 요청
  requested_at timestamptz,
  requested_by uuid references public.users (id) on delete set null,
  primary key (couple_id, user_id)
);

alter table public.couple_refresh_state enable row level security;

-- 읽기는 지난 커플까지. 쓰기는 아래 RPC로만 한다(couples와 같은 원칙, 설계 9장)
create policy couple_refresh_state_select on public.couple_refresh_state
  for select to authenticated using (couple_id in (select private.my_couple_ids()));
revoke all on public.couple_refresh_state from anon, authenticated;
grant select on public.couple_refresh_state to authenticated;

-- 상대에게 요청한다. 같은 사람이 1시간 안에 다시 보내지 못한다
create function public.request_refresh() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid := private.my_couple_id();
  partner uuid;
begin
  if me is null or couple is null then raise exception 'no_active_couple'; end if;
  select case when c.user_a_id = me then c.user_b_id else c.user_a_id end into partner
    from public.couples c where c.id = couple;
  if exists (
    select 1 from public.couple_refresh_state s
    where s.couple_id = couple and s.user_id = partner and s.requested_by = me
      and s.requested_at > now() - interval '1 hour'
  ) then raise exception 'too_soon'; end if;
  insert into public.couple_refresh_state (couple_id, user_id, requested_at, requested_by)
    values (couple, partner, now(), me)
    on conflict (couple_id, user_id) do update
      set requested_at = excluded.requested_at, requested_by = excluded.requested_by;
end $$;
revoke all on function public.request_refresh() from public, anon;
grant execute on function public.request_refresh() to authenticated;

-- 비교할 기록 저장 직후 앱이 부른다. 내 최신화 시각을 남기고 받은 요청을 지운다
create function public.mark_refreshed() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid := private.my_couple_id();
begin
  if me is null or couple is null then raise exception 'no_active_couple'; end if;
  insert into public.couple_refresh_state (couple_id, user_id, refreshed_at)
    values (couple, me, now())
    on conflict (couple_id, user_id) do update
      set refreshed_at = excluded.refreshed_at, requested_at = null, requested_by = null;
end $$;
revoke all on function public.mark_refreshed() from public, anon;
grant execute on function public.mark_refreshed() to authenticated;

-- 다른 테이블과 같은 비공개 무효화 알림(마이그레이션 11)
create trigger notify_insert after insert on public.couple_refresh_state
  referencing new table as changed_rows for each statement
  execute function private.notify_couple_change('refresh', 'couple_id', 'couple:');
create trigger notify_update after update on public.couple_refresh_state
  referencing old table as old_rows new table as new_rows for each statement
  execute function private.notify_couple_change('refresh', 'couple_id', 'couple:');
create trigger notify_delete after delete on public.couple_refresh_state
  referencing old table as changed_rows for each statement
  execute function private.notify_couple_change('refresh', 'couple_id', 'couple:');
