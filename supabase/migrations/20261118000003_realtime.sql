-- 상대의 확인·버림·생활권 수정·사진 추가를 앱에 바로 반영한다(설계 5.4, 12장).
-- Realtime은 RLS를 따르므로 각자 자기 커플의 변경만 받는다. photo_days는 본인만
-- 읽을 수 있어 상대 변경이 오지 않으므로 넣지 않고, 앱 복귀 때 다시 읽는다
alter publication supabase_realtime
  add table public.trips, public.trip_regions, public.couple_region_overrides,
            public.couples, public.photos;
