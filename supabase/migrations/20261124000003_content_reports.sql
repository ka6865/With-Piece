create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  couple_id uuid not null,
  target_kind text not null check (target_kind in ('photo', 'trip_comment', 'photo_comment')),
  target_id uuid not null,
  reason text not null check (reason in ('inappropriate', 'harassment', 'privacy', 'other')),
  created_at timestamptz not null default now(),
  unique (reporter_id, target_kind, target_id)
);

alter table public.content_reports enable row level security;
revoke all on public.content_reports from public, anon, authenticated, service_role;
grant select on public.content_reports to service_role;

create function public.submit_content_report(p_kind text, p_target_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user_id uuid := auth.uid();
  v_couple_id uuid;
begin
  if v_user_id is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_reason is null or p_reason not in ('inappropriate', 'harassment', 'privacy', 'other') then
    raise exception 'invalid report reason' using errcode = '22023';
  end if;
  if p_kind = 'photo' then
    select couple_id into v_couple_id from public.photos where id = p_target_id and couple_id in (select private.my_couple_ids());
  elsif p_kind = 'trip_comment' then
    select couple_id into v_couple_id from public.guestbook_entries where id = p_target_id and couple_id in (select private.my_couple_ids());
  elsif p_kind = 'photo_comment' then
    select couple_id into v_couple_id from public.photo_comments where id = p_target_id and couple_id in (select private.my_couple_ids());
  else
    raise exception 'invalid report target' using errcode = '22023';
  end if;
  if v_couple_id is null then
    raise exception 'target unavailable' using errcode = '42501';
  end if;
  insert into public.content_reports(reporter_id, couple_id, target_kind, target_id, reason)
  values (v_user_id, v_couple_id, p_kind, p_target_id, p_reason)
  on conflict (reporter_id, target_kind, target_id) do nothing;
end
$$;

revoke all on function public.submit_content_report(text, uuid, text) from public, anon;
grant execute on function public.submit_content_report(text, uuid, text) to authenticated;
