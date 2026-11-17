-- 설계 문서 9장. 읽기는 아카이브까지 포함한 소속 커플, 쓰기는 활성 커플 하나로 판정한다.

-- 정책 안에서 couples를 다시 조회하면 재귀에 걸리므로 SECURITY DEFINER로 감싼다
create function private.my_couple_id() returns uuid
language sql stable security definer set search_path = '' as $$
  select active_couple_id from public.users where id = (select auth.uid());
$$;

create function private.my_couple_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select id from public.couples
  where user_a_id = (select auth.uid()) or user_b_id = (select auth.uid());
$$;

grant usage on schema private to authenticated;
grant execute on function private.my_couple_id(), private.my_couple_ids() to authenticated;

alter table public.regions enable row level security;
alter table public.users enable row level security;
alter table public.couples enable row level security;
alter table public.couple_invites enable row level security;
alter table public.invite_attempts enable row level security;
alter table public.photo_days enable row level security;
alter table public.couple_region_overrides enable row level security;
alter table public.trips enable row level security;
alter table public.trip_regions enable row level security;
alter table public.photos enable row level security;

create policy regions_select on public.regions
  for select to anon, authenticated using (true);

-- 본인과 소속 커플(아카이브 포함)의 상대
create policy users_select on public.users
  for select to authenticated using (
    id = (select auth.uid())
    or exists (
      select 1 from public.couples c
      where c.id in (select private.my_couple_ids())
        and users.id in (c.user_a_id, c.user_b_id)
    )
  );

create policy users_update on public.users
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- 커플·삭제 상태는 RPC만 바꾼다. 클라이언트는 프로필 열만 쓴다
revoke update on public.users from anon, authenticated;
grant update (nickname, avatar_url, home_region_id) on public.users to authenticated;

create policy couples_select on public.couples
  for select to authenticated using (id in (select private.my_couple_ids()));

-- couple_invites, invite_attempts는 RPC만 다룬다. 정책 없이 RLS만 켠다

create policy photo_days_select on public.photo_days
  for select to authenticated using (user_id = (select auth.uid()));
create policy photo_days_insert on public.photo_days
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy photo_days_update on public.photo_days
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
create policy photo_days_delete on public.photo_days
  for delete to authenticated using (user_id = (select auth.uid()));

-- 커플 소유 테이블은 모두 같은 네 정책을 갖는다
do $$
declare
  t text;
begin
  foreach t in array array['couple_region_overrides', 'trips', 'trip_regions', 'photos'] loop
    execute format(
      'create policy %1$s_select on public.%1$I for select to authenticated
         using (couple_id in (select private.my_couple_ids()))', t);
    execute format(
      'create policy %1$s_insert on public.%1$I for insert to authenticated
         with check (couple_id = (select private.my_couple_id()))', t);
    execute format(
      'create policy %1$s_update on public.%1$I for update to authenticated
         using (couple_id = (select private.my_couple_id()))
         with check (couple_id = (select private.my_couple_id()))', t);
    execute format(
      'create policy %1$s_delete on public.%1$I for delete to authenticated
         using (couple_id = (select private.my_couple_id()))', t);
  end loop;
end $$;

-- 사진 버킷. 경로 첫 세그먼트가 couple_id다(설계 8.2, 9.2). uuid가 아니면 캐스트가 실패해 거부된다.
-- UPDATE 정책은 두지 않는다. 사진은 덮어쓰지 않고 지운 뒤 새로 올린다
create policy photos_bucket_select on storage.objects
  for select to authenticated using (
    bucket_id = 'photos'
    and (storage.foldername(name))[1]::uuid in (select private.my_couple_ids())
  );

create policy photos_bucket_insert on storage.objects
  for insert to authenticated with check (
    bucket_id = 'photos'
    and (storage.foldername(name))[1]::uuid = (select private.my_couple_id())
  );

create policy photos_bucket_delete on storage.objects
  for delete to authenticated using (
    bucket_id = 'photos'
    and (storage.foldername(name))[1]::uuid = (select private.my_couple_id())
  );
