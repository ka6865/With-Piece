-- 설계 문서 5.2, 6.2, 9.3. 커플 관계와 초대는 이 함수들로만 바뀐다.

-- 혼동 문자(0 O o 1 l I)를 뺀 56자에서 10자. 바이트 224(=56*4) 이상은 버려 모듈로 편향을 없앤다
create function private.new_invite_code() returns text
language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := '23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz';
  bytes bytea;
  code text := '';
  b int;
begin
  while length(code) < 10 loop
    bytes := extensions.gen_random_bytes(16);
    for i in 0 .. 15 loop
      b := get_byte(bytes, i);
      if b < 224 and length(code) < 10 then
        code := code || substr(alphabet, b % 56 + 1, 1);
      end if;
    end loop;
  end loop;
  return code;
end $$;

create function public.create_invite()
returns table (code text, expires_at timestamptz)
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
begin
  if (select active_couple_id from public.users where id = me) is not null then
    raise exception 'already_coupled';
  end if;
  -- 부분 유일 인덱스가 만료를 보지 않으므로 만료된 미수락 초대를 먼저 지운다(설계 6.2)
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

create function public.my_invite()
returns table (code text, expires_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select i.code, i.expires_at from public.couple_invites i
  where i.inviter_id = auth.uid() and i.accepted_at is null and i.expires_at > now();
$$;

-- 실패는 예외가 아니라 상태값으로 돌려준다. 예외를 던지면 실패 기록이 함께 롤백되어
-- 속도 제한이 동작하지 않는다(설계 9.3)
create function public.join_couple(p_code text) returns text
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

  -- 동시 수락 경합과 교착을 막으려고 두 사람 행을 id 순서로 잠근 뒤 다시 읽는다
  perform 1 from public.users where id in (me, inv.inviter_id) order by id for update;
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

create function public.set_started_on(p_date date) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_date > current_date then
    raise exception 'future_date';
  end if;
  update public.couples set started_on = p_date where id = private.my_couple_id();
  if not found then
    raise exception 'no_active_couple';
  end if;
end $$;

create function public.archive_couple() returns void
language plpgsql security definer set search_path = '' as $$
declare
  couple uuid := private.my_couple_id();
begin
  if couple is null then
    raise exception 'no_active_couple';
  end if;
  update public.couples set status = 'archived', archived_at = now() where id = couple;
  update public.users set active_couple_id = null where active_couple_id = couple;
end $$;

-- 두 사람의 원본 목록은 이 함수 밖으로 나가지 않고 교집합만 나간다(설계 5.2)
create function public.couple_matched_days()
returns table (day date, region_id text)
language sql stable security definer set search_path = '' as $$
  select a.day, a.region_id
  from public.couples c
  join public.photo_days a on a.user_id = c.user_a_id
  join public.photo_days b
    on b.user_id = c.user_b_id and b.day = a.day and b.region_id = a.region_id
  where c.id = private.my_couple_id()
    and c.started_on is not null
    and a.day >= c.started_on
  order by a.day, a.region_id;
$$;

do $$
declare
  f text;
begin
  foreach f in array array[
    'public.create_invite()', 'public.my_invite()', 'public.join_couple(text)',
    'public.set_started_on(date)', 'public.archive_couple()', 'public.couple_matched_days()'
  ] loop
    execute format('revoke execute on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

revoke execute on function private.new_invite_code() from public;
