-- 삭제 요청·정리·Storage 제거를 직렬화하고 재시도할 수 있게 한다.

alter table public.users add column deletion_started_at timestamptz;

drop policy photos_update on public.photos;
drop policy photos_insert on public.photos;
create policy photos_insert on public.photos
  for insert to authenticated
  with check (
    couple_id = (select private.my_couple_id())
    and uploaded_by = (select auth.uid())
  );

create or replace function public.request_account_deletion() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid;
  requested_at timestamptz;
  started_at timestamptz;
begin
  select active_couple_id, deletion_requested_at, deletion_started_at
    into couple, requested_at, started_at
    from public.users where id = me for update;
  if requested_at is not null then
    return;
  end if;
  if started_at is not null then
    raise exception 'deletion_started';
  end if;
  update public.users set deletion_requested_at = now() where id = me;
  if couple is not null then
    update public.couples set status = 'archived', archived_at = now() where id = couple;
    update public.users set active_couple_id = null where active_couple_id = couple;
  end if;
  delete from public.photo_days where user_id = me;
end $$;

create or replace function public.cancel_account_deletion() returns void
language plpgsql security definer set search_path = '' as $$
declare
  requested_at timestamptz;
  started_at timestamptz;
begin
  select deletion_requested_at, deletion_started_at into requested_at, started_at
  from public.users where id = auth.uid() for update;
  if started_at is not null then
    raise exception 'deletion_started';
  end if;
  if requested_at is null then
    raise exception 'no_deletion_request';
  end if;
  if requested_at <= now() - interval '30 days' then
    raise exception 'deletion_expired';
  end if;
  update public.users set deletion_requested_at = null where id = auth.uid();
end $$;

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
    values (me, private.new_invite_code(), now() + interval '7 days')
    returning i.code, i.expires_at;
end $$;

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
  insert into public.invite_attempts (user_id, succeeded) values (me, true);
  return 'ok';
end $$;

create or replace function public.purge_expired_users()
returns table (user_id uuid, object_paths text[])
language plpgsql security definer set search_path = '' as $$
declare
  expired uuid;
  paths text[];
begin
  for expired in
    select u.id from public.users u
    where u.deletion_requested_at <= now() - interval '30 days'
    order by u.id for update skip locked
  loop
    update public.users set deletion_started_at = coalesce(deletion_started_at, now())
      where id = expired;
    select coalesce(array_agg(regexp_replace(p.object_key, '/([^/]+)$', '/' || s.size || '/\1')
                              order by p.object_key, s.size), '{}')
      into paths
      from public.photos p
      join public.couples c on c.id = p.couple_id
      cross join (values ('full'), ('thumb')) as s(size)
      where expired in (c.user_a_id, c.user_b_id);
    user_id := expired;
    object_paths := paths;
    return next;
  end loop;
end $$;

create or replace function public.finalize_expired_user(p_user_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  requested_at timestamptz;
  started_at timestamptz;
begin
  perform 1 from public.users u
    where u.id = p_user_id
       or u.id in (
         select c.user_a_id from public.couples c where p_user_id in (c.user_a_id, c.user_b_id)
         union
         select c.user_b_id from public.couples c where p_user_id in (c.user_a_id, c.user_b_id)
       )
    order by u.id for update;
  select deletion_requested_at, deletion_started_at into requested_at, started_at
    from public.users where id = p_user_id;
  if not found then
    return;
  end if;
  if started_at is null or requested_at > now() - interval '30 days' then
    raise exception 'deletion_not_started';
  end if;
  update public.users set active_couple_id = null
    where active_couple_id in (select id from public.couples where p_user_id in (user_a_id, user_b_id));
  delete from public.couple_invites where inviter_id = p_user_id or accepted_by = p_user_id;
  delete from public.couples where p_user_id in (user_a_id, user_b_id);
end $$;

revoke execute on function public.finalize_expired_user(uuid) from public, anon, authenticated;
grant execute on function public.finalize_expired_user(uuid) to service_role;
