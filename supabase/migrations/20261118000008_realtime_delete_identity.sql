-- 커플 필터가 삭제 전 couple_id를 확인할 수 있게 이전 행을 발행한다.
alter table public.photos replica identity full;
alter table public.trip_regions replica identity full;
alter table public.couple_region_overrides replica identity full;
