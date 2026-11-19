-- 조각별 대표 사진과 구도(조각채우기·최신화·대표사진 설계 4.3). 커플·조각당 한 행.
-- 행이 없으면 앱이 그 조각의 가장 최근 사진을 자동 대표로 쓴다
create table public.region_covers (
  couple_id uuid not null references public.couples (id) on delete cascade,
  region_id text not null references public.regions (id),
  photo_id uuid not null,
  -- 조각 bbox를 덮는 최소 배율 대비 배수
  scale real not null check (scale >= 1 and scale <= 8),
  -- 조각 bbox 중심에 오는 사진 위 점(너비·높이 대비 0~1)
  center_x real not null check (center_x between 0 and 1),
  center_y real not null check (center_y between 0 and 1),
  updated_by uuid not null default auth.uid() references public.users (id) on delete cascade,
  updated_at timestamptz not null default now(),
  primary key (couple_id, region_id),
  -- 같은 커플 사진만 가리키고, 사진이 지워지면 함께 지워진다
  foreign key (photo_id, couple_id) references public.photos (id, couple_id) on delete cascade
);

alter table public.region_covers enable row level security;

-- 사진이 그 조각에서 찍힌 것이어야 한다
create function private.cover_photo_matches(p_photo uuid, p_region text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.photos where id = p_photo and region_id = p_region);
$$;
revoke all on function private.cover_photo_matches(uuid, text) from public, anon;
grant execute on function private.cover_photo_matches(uuid, text) to authenticated;

-- 읽기는 지난 커플까지, 쓰기는 활성 커플의 두 사람 누구나(나중 것이 남는다)
create policy region_covers_select on public.region_covers
  for select to authenticated using (couple_id in (select private.my_couple_ids()));
create policy region_covers_insert on public.region_covers
  for insert to authenticated with check (
    couple_id = (select private.my_couple_id())
    and private.cover_photo_matches(photo_id, region_id));
create policy region_covers_update on public.region_covers
  for update to authenticated
  using (couple_id = (select private.my_couple_id()))
  with check (
    couple_id = (select private.my_couple_id())
    and private.cover_photo_matches(photo_id, region_id));
create policy region_covers_delete on public.region_covers
  for delete to authenticated using (couple_id = (select private.my_couple_id()));

-- 바꾼 사람과 시각은 서버가 정한다
create function private.touch_region_cover() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end $$;
revoke all on function private.touch_region_cover() from public, anon, authenticated;
create trigger region_covers_touch before insert or update on public.region_covers
  for each row execute function private.touch_region_cover();

revoke all on public.region_covers from anon, authenticated;
grant select, delete on public.region_covers to authenticated;
grant insert (couple_id, region_id, photo_id, scale, center_x, center_y) on public.region_covers to authenticated;
grant update (photo_id, scale, center_x, center_y) on public.region_covers to authenticated;

-- 다른 테이블과 같은 비공개 무효화 알림(마이그레이션 11)
create trigger notify_insert after insert on public.region_covers
  referencing new table as changed_rows for each statement
  execute function private.notify_couple_change('covers', 'couple_id', 'couple:');
create trigger notify_update after update on public.region_covers
  referencing old table as old_rows new table as new_rows for each statement
  execute function private.notify_couple_change('covers', 'couple_id', 'couple:');
create trigger notify_delete after delete on public.region_covers
  referencing old table as changed_rows for each statement
  execute function private.notify_couple_change('covers', 'couple_id', 'couple:');
