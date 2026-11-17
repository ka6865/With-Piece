-- 설계 문서 6장의 MVP 스키마. 2차 테이블(expenses, guestbook_entries)은 5단계에서 더한다.

create extension if not exists pgcrypto with schema extensions;
create schema if not exists private;

-- 지역 기준 데이터. 행은 20261117000002_regions.sql(생성 파일)이 넣는다
create table public.regions (
  id text primary key,
  name text not null,
  parent_id text references public.regions (id),
  depth int not null check (depth in (1, 2))
);

create table public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text,
  avatar_url text,
  active_couple_id uuid,
  home_region_id text references public.regions (id),
  deletion_requested_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.couples (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references public.users (id),
  user_b_id uuid not null references public.users (id),
  started_on date,
  status text not null default 'active' check (status in ('active', 'archived')),
  connected_at timestamptz not null default now(),
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  check (user_a_id <> user_b_id)
);

-- 활성 커플은 사람당 하나. 단일 컬럼이라 구조적으로 성립한다(설계 6.2)
alter table public.users
  add constraint users_active_couple_fk
  foreign key (active_couple_id) references public.couples (id);

create table public.couple_invites (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references public.users (id) on delete cascade,
  code text not null unique,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  check ((accepted_at is null) = (accepted_by is null))
);

create unique index couple_invites_one_open
  on public.couple_invites (inviter_id)
  where accepted_at is null;

create table public.invite_attempts (
  user_id uuid not null references public.users (id) on delete cascade,
  attempted_at timestamptz not null default now(),
  succeeded boolean not null
);

create index invite_attempts_user_time on public.invite_attempts (user_id, attempted_at);

create table public.photo_days (
  user_id uuid not null references public.users (id) on delete cascade,
  day date not null,
  region_id text not null references public.regions (id),
  photo_count int not null check (photo_count > 0),
  primary key (user_id, day, region_id)
);

create table public.couple_region_overrides (
  couple_id uuid not null references public.couples (id) on delete cascade,
  region_id text not null references public.regions (id),
  kind text not null check (kind in ('home', 'travel')),
  updated_by uuid references public.users (id),
  updated_at timestamptz not null default now(),
  primary key (couple_id, region_id)
);

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete cascade,
  title text not null,
  started_on date not null,
  ended_on date not null,
  status text not null check (status in ('confirmed', 'dismissed')),
  source text not null check (source in ('auto', 'manual')),
  cover_photo_id uuid,
  created_by uuid references public.users (id),
  created_at timestamptz not null default now(),
  check (ended_on >= started_on),
  -- 딸린 행이 (trip_id, couple_id)로 참조한다. 단일 외래키면 남의 여행 id에
  -- 자기 couple_id를 붙인 행이 RLS를 통과한다(설계 6.2)
  unique (id, couple_id)
);

create table public.trip_regions (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null,
  couple_id uuid not null,
  region_id text not null references public.regions (id),
  created_at timestamptz not null default now(),
  unique (trip_id, region_id),
  foreign key (trip_id, couple_id) references public.trips (id, couple_id) on delete cascade
);

create table public.photos (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null,
  couple_id uuid not null,
  region_id text references public.regions (id),
  object_key text not null unique,
  width int not null,
  height int not null,
  byte_size int not null,
  caption text,
  taken_at timestamptz,
  uploaded_by uuid not null default auth.uid() references public.users (id),
  created_at timestamptz not null default now(),
  foreign key (trip_id, couple_id) references public.trips (id, couple_id) on delete cascade
);

alter table public.trips
  add constraint trips_cover_photo_fk
  foreign key (cover_photo_id) references public.photos (id) on delete set null;

-- 방문한 조각만 돌려준다. 미방문은 클라이언트가 애셋에서 뺀다(설계 6.3)
create view public.couple_visited_regions
with (security_invoker = true) as
select tr.couple_id,
       tr.region_id,
       r.parent_id,
       r.name,
       min(tr.created_at) as first_visited_at,
       count(*) as visit_count
from public.trip_regions tr
join public.trips t on t.id = tr.trip_id and t.status = 'confirmed'
join public.regions r on r.id = tr.region_id
group by tr.couple_id, tr.region_id, r.parent_id, r.name;

-- 가입 시 public.users 행을 만든다
create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.users (id, nickname)
  values (new.id, new.raw_user_meta_data ->> 'name');
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

insert into storage.buckets (id, name, public) values ('photos', 'photos', false);
