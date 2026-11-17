-- 계정 삭제 30일 유예와 하루 1회 정리 작업(설계 8.3, 14.1).
-- Storage 객체는 SQL로 지울 수 없으므로 정리 함수는 지울 경로를 돌려주고,
-- Edge Function(daily-cleanup)이 Storage API로 지운다.

-- 요청 즉시 커플을 아카이브해 두 사람 모두 새 기록을 쓸 수 없게 하고,
-- 위치 기록(photo_days)은 가장 먼저 지운다
create function public.request_account_deletion() returns void
language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  couple uuid;
begin
  select active_couple_id into couple from public.users where id = me for update;
  update public.users set deletion_requested_at = now() where id = me;
  if couple is not null then
    update public.couples set status = 'archived', archived_at = now() where id = couple;
    update public.users set active_couple_id = null where active_couple_id = couple;
  end if;
  delete from public.photo_days where user_id = me;
end $$;

-- 커플은 되살리지 않는다. 다시 이어지려면 새로 초대한다(설계 14.1)
create function public.cancel_account_deletion() returns void
language sql security definer set search_path = '' as $$
  update public.users set deletion_requested_at = null where id = auth.uid();
$$;

-- 유예가 끝난 사용자가 속했던 커플을 지우고(여행·조각·사진 행은 cascade),
-- 그 커플의 사진 파일 경로(상세·썸네일)를 돌려준다. 계정 자체는 함수가 auth API로 지운다
create function public.purge_expired_users()
returns table (user_id uuid, object_paths text[])
language plpgsql security definer set search_path = '' as $$
declare
  expired uuid;
  paths text[];
begin
  for expired in
    select u.id from public.users u
    where u.deletion_requested_at < now() - interval '30 days'
    order by u.id
  loop
    select coalesce(array_agg(regexp_replace(p.object_key, '/([^/]+)$', '/' || s.size || '/\1')
                              order by p.object_key, s.size), '{}')
      into paths
      from public.photos p
      join public.couples c on c.id = p.couple_id
      cross join (values ('full'), ('thumb')) as s(size)
      where expired in (c.user_a_id, c.user_b_id);
    update public.users set active_couple_id = null
      where active_couple_id in (
        select id from public.couples where expired in (user_a_id, user_b_id));
    delete from public.couple_invites where accepted_by = expired;
    delete from public.couples where expired in (user_a_id, user_b_id);
    user_id := expired;
    object_paths := paths;
    return next;
  end loop;
end $$;

-- photos 행이 없는 24시간 넘은 사진 파일. 업로드 중인 파일은 건드리지 않는다(설계 8.3)
create function public.orphan_photo_paths() returns setof text
language sql stable security definer set search_path = '' as $$
  select o.name from storage.objects o
  where o.bucket_id = 'photos'
    and o.created_at < now() - interval '24 hours'
    and not exists (
      select 1 from public.photos p
      where p.object_key = regexp_replace(o.name, '/(full|thumb)/', '/')
    )
  order by o.name;
$$;

create function public.cleanup_stale() returns void
language sql security definer set search_path = '' as $$
  delete from public.couple_invites where accepted_at is null and expires_at <= now();
  delete from public.invite_attempts where attempted_at < now() - interval '24 hours';
$$;

revoke execute on function public.request_account_deletion() from public, anon;
revoke execute on function public.cancel_account_deletion() from public, anon;
grant execute on function public.request_account_deletion() to authenticated;
grant execute on function public.cancel_account_deletion() to authenticated;

-- 정리 함수는 service role(Edge Function)만 부른다
revoke execute on function public.purge_expired_users() from public, anon, authenticated;
revoke execute on function public.orphan_photo_paths() from public, anon, authenticated;
revoke execute on function public.cleanup_stale() from public, anon, authenticated;
grant execute on function public.purge_expired_users() to service_role;
grant execute on function public.orphan_photo_paths() to service_role;
grant execute on function public.cleanup_stale() to service_role;
