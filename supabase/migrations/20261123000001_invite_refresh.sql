-- 연결 코드 정리(2026-11-23 설계 ①). 유효 기간 3일, 연결되면 두 사람의 열린 코드를 지우고,
-- 코드를 새로 받아 옛 코드를 바로 무효로 만들 수 있다.

-- 이미 연결된 사람에게 남아 있는 열린 코드는 끊은 뒤 옛 상대가 쓸 수 있으므로 지운다
delete from public.couple_invites i
  using public.users u
  where u.id = i.inviter_id and u.active_couple_id is not null and i.accepted_at is null;
update public.couple_invites set expires_at = least(expires_at, created_at + interval '3 days')
  where accepted_at is null;

create or replace function public.create_invite()
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  requested_at timestamptz;
  started_at timestamptz;
  couple uuid;
begin
  select u.deletion_requested_at, u.deletion_started_at, u.active_couple_id
    into requested_at, started_at, couple
    from public.users u where u.id = me for update;
  if requested_at is not null or started_at is not null then
    raise exception 'deletion_pending';
  end if;
  if couple is not null then
    raise exception 'already_coupled';
  end if;
  delete from public.couple_invites i
    where i.inviter_id = me and i.accepted_at is null and i.expires_at <= now();
  return query
    select i.code, i.expires_at from public.couple_invites i
    where i.inviter_id = me and i.accepted_at is null;
  if found then
    return;
  end if;
  return query
    insert into public.couple_invites as i (inviter_id, code, expires_at)
    values (me, private.new_invite_code(), now() + interval '3 days')
    returning i.code, i.expires_at;
end $$;

-- 내 열린 코드를 지우고 새로 만든다. 검사는 create_invite가 한다
create function public.regenerate_invite()
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
begin
  delete from public.couple_invites i
    where i.inviter_id = auth.uid() and i.accepted_at is null;
  return query select * from public.create_invite();
end $$;
revoke execute on function public.regenerate_invite() from public, anon;
grant execute on function public.regenerate_invite() to authenticated;

create or replace function public.join_couple(p_code text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  inv public.couple_invites;
  couple uuid;
begin
  if (select count(*) from public.invite_attempts
        where user_id = me and not succeeded and attempted_at > now() - interval '1 minute') >= 5
     or (select count(*) from public.invite_attempts
        where user_id = me and not succeeded and attempted_at > now() - interval '1 hour') >= 20 then
    return 'rate_limited';
  end if;
  select * into inv from public.couple_invites where code = p_code for update;
  if not found then
    insert into public.invite_attempts (user_id, succeeded) values (me, false);
    return 'invalid_code';
  end if;
  if inv.accepted_at is not null or inv.expires_at <= now() then
    insert into public.invite_attempts (user_id, succeeded) values (me, false);
    return 'expired';
  end if;
  if inv.inviter_id = me then
    insert into public.invite_attempts (user_id, succeeded) values (me, false);
    return 'self';
  end if;

  -- 가입·삭제 요청 경합에서 기존 id 오름차순 잠금 순서를 유지한다.
  perform 1 from public.users where id in (me, inv.inviter_id) order by id for update;
  if exists (select 1 from public.users
             where id in (me, inv.inviter_id)
               and (deletion_requested_at is not null or deletion_started_at is not null)) then
    insert into public.invite_attempts (user_id, succeeded) values (me, false);
    return 'deletion_pending';
  end if;
  if exists (select 1 from public.users
             where id in (me, inv.inviter_id) and active_couple_id is not null) then
    insert into public.invite_attempts (user_id, succeeded) values (me, false);
    return 'already_coupled';
  end if;

  insert into public.couples (user_a_id, user_b_id) values (inv.inviter_id, me)
    returning id into couple;
  update public.users set active_couple_id = couple where id in (me, inv.inviter_id);
  update public.couple_invites set accepted_at = now(), accepted_by = me where id = inv.id;
  -- 연결 뒤에 남은 두 사람의 다른 열린 코드는 끊은 뒤 옛 상대가 쓸 수 있으므로 지운다
  delete from public.couple_invites i
    where i.inviter_id in (me, inv.inviter_id) and i.accepted_at is null;
  insert into public.invite_attempts (user_id, succeeded) values (me, true);
  return 'ok';
end $$;
