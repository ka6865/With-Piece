-- 대표 사진 후보를 넓힌다(2026-11-20 사용자 결정). 그 조각에서 찍은 사진뿐 아니라
-- 그 조각이 들어간 여행의 사진도 고를 수 있다. 가평에서 찍은 사진이 없는 춘천·가평
-- 여행이면 춘천 사진을 가평의 대표로 쓸 수 있다
create or replace function private.cover_photo_matches(p_photo uuid, p_region text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.photos p
    where p.id = p_photo
      and (p.region_id = p_region
        or exists (
          select 1 from public.trip_regions tr
          where tr.trip_id = p.trip_id and tr.region_id = p_region
        ))
  );
$$;
