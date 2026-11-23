-- 여행 지우기(설계 8.4 "여행 지우기", 2026-11-23). 활성 커플의 두 사람 누구든 상대 사진까지
-- 여행을 통째로 지운다. photos 삭제 정책은 올린 사람만이라 SECURITY DEFINER로 처리한다.
-- 자동 여행은 행을 지우면 같은 기간이 다시 후보로 뜨므로 버린 여행으로 바꾼다.
-- 사진 파일은 지우지 않는다. 내 파일은 클라이언트가, 나머지는 정리 작업이 지운다(설계 8.3)
create function public.delete_trip(p_trip_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  couple uuid := private.my_couple_id();
  t public.trips;
begin
  select * into t from public.trips
    where id = p_trip_id and couple_id = couple and status = 'confirmed'
    for update;
  if couple is null or not found then
    raise exception 'trip_not_found';
  end if;
  if t.source = 'manual' then
    -- 사진·조각·방명록은 외래키로 함께 지워진다
    delete from public.trips where id = t.id;
    return;
  end if;
  update public.trips set cover_photo_id = null where id = t.id;
  delete from public.photos where trip_id = t.id;
  delete from public.trip_regions where trip_id = t.id;
  delete from public.guestbook_entries where trip_id = t.id;
  update public.trips set status = 'dismissed', title = '' where id = t.id;
end $$;

revoke execute on function public.delete_trip(uuid) from public, anon;
grant execute on function public.delete_trip(uuid) to authenticated;
