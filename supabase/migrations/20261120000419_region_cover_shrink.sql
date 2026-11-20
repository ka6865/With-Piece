-- 대표 사진을 축소해 조각 안에 다 보이게 할 수 있다. 빈 곳은 흰색이나 검은색으로 칠한다.
-- 축소하면 조각 bbox 중심이 사진 밖에 올 수 있어 중심 범위도 넓힌다(배율 0.25면 -1~2)
alter table public.region_covers
  drop constraint region_covers_scale_check,
  drop constraint region_covers_center_x_check,
  drop constraint region_covers_center_y_check,
  add constraint region_covers_scale_check check (scale >= 0.25 and scale <= 8),
  add constraint region_covers_center_x_check check (center_x between -1 and 2),
  add constraint region_covers_center_y_check check (center_y between -1 and 2),
  add column black_background boolean not null default false;

grant insert (black_background) on public.region_covers to authenticated;
grant update (black_background) on public.region_covers to authenticated;
