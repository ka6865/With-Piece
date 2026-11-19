-- 개발 전용: 상대 없이 혼자 테스트하기 위한 "테스트 상대".
-- 마이그레이션이 아니다. 로컬 스택은 db reset 시드로, 클라우드는 개발 프로젝트에만 직접 적용한다.
-- 출시용 프로젝트에는 절대 적용하지 않는다. 앱도 DEV_SOLO 빌드에서만 이 함수를 부른다.
-- 다시 적용해도 되도록 create or replace / drop if exists로 쓴다.

-- 테스트 상대 계정을 만들어 커플로 잇고, 이미 있는 내 photo_days를 복사한다
create or replace function public.dev_solo_join() returns text
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  partner uuid := gen_random_uuid();
  couple uuid;
begin
  if me is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if (select active_couple_id from public.users where id = me) is not null then
    return 'already_coupled';
  end if;
  insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    -- 연결을 끊고 다시 BGMS를 넣으면 새 상대를 만든다. 이메일이 겹치지 않게 새 id로 짓는다
    values (partner, 'authenticated', 'authenticated', 'solo-' || partner || '@dev.local',
            '{"dev_solo": true}', '{"name": "테스트 상대"}', now(), now());
  insert into public.couples (user_a_id, user_b_id) values (me, partner) returning id into couple;
  update public.users set active_couple_id = couple where id in (me, partner);
  insert into public.photo_days (user_id, day, region_id, photo_count)
    select partner, day, region_id, photo_count from public.photo_days where user_id = me;
  return 'ok';
end $$;

revoke execute on function public.dev_solo_join() from public, anon;
grant execute on function public.dev_solo_join() to authenticated;

-- 테스트 상대의 photo_days가 내 변경을 그대로 따라가 교집합이 내 기록 전체가 된다
create or replace function private.dev_solo_mirror() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  owner uuid := coalesce(new.user_id, old.user_id);
  partner uuid;
begin
  select case when c.user_a_id = owner then c.user_b_id else c.user_a_id end into partner
    from public.users u join public.couples c on c.id = u.active_couple_id
    where u.id = owner;
  if partner is null or not exists (
    select 1 from auth.users where id = partner and raw_app_meta_data ->> 'dev_solo' = 'true'
  ) then
    return null;
  end if;
  if tg_op = 'DELETE' then
    delete from public.photo_days
      where user_id = partner and day = old.day and region_id = old.region_id;
  else
    insert into public.photo_days (user_id, day, region_id, photo_count)
      values (partner, new.day, new.region_id, new.photo_count)
      on conflict (user_id, day, region_id) do update set photo_count = excluded.photo_count;
  end if;
  return null;
end $$;

drop trigger if exists dev_solo_mirror on public.photo_days;
create trigger dev_solo_mirror
  after insert or update or delete on public.photo_days
  for each row execute function private.dev_solo_mirror();


-- 개발 상대도 내 승인 범위만 따른다. 원본 미승인 기록은 자동 비교하지 않는다.
create or replace function private.dev_solo_share_mirror() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  owner uuid := coalesce(new.user_id, old.user_id);
  couple uuid := coalesce(new.couple_id, old.couple_id);
  partner uuid;
begin
  select case when c.user_a_id = owner then c.user_b_id else c.user_a_id end
    into partner from public.couples c where c.id = couple;
  if partner is null or not exists (
    select 1 from auth.users where id = partner and raw_app_meta_data ->> 'dev_solo' = 'true'
  ) then return null; end if;
  if tg_op = 'DELETE' then
    delete from public.photo_day_shares where couple_id = couple and user_id = partner
      and day = old.day and region_id = old.region_id;
  else
    insert into public.photo_day_shares(couple_id, user_id, day, region_id)
      values(couple, partner, new.day, new.region_id) on conflict do nothing;
  end if;
  return null;
end $$;
drop trigger if exists dev_solo_share_mirror on public.photo_day_shares;
create trigger dev_solo_share_mirror after insert or delete on public.photo_day_shares
  for each row execute function private.dev_solo_share_mirror();
