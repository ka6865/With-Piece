-- DELETE는 행 RLS를 거치지 않으므로 원본 행 발행을 없애고 비공개 무효화 알림만 보낸다.
alter publication supabase_realtime drop table
  public.trips, public.trip_regions, public.couple_region_overrides, public.couples, public.photos;
alter table public.photos replica identity default;
alter table public.trip_regions replica identity default;
alter table public.couple_region_overrides replica identity default;
alter table public.trips replica identity default;
alter table public.couples replica identity default;

-- 아카이브 읽기 권한은 유지한다. 비교 승인은 현재 커플만, 연결 대기는 본인만 받는다.
create policy couple_invalidation_receive on realtime.messages
  for select to authenticated using (
    extension = 'broadcast' and topic = (select realtime.topic())
    and (
      topic in (select 'couple:' || id::text from private.my_couple_ids() id)
      or topic = 'couple-shares:' || (select private.my_couple_id())::text
      or topic = 'user:' || (select auth.uid())::text
    )
  );

-- 전이 테이블로 일괄 변경과 FK 연쇄 삭제의 행 수가 알림 수에 드러나지 않게 한다.
create function private.notify_couple_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  couple uuid;
  changed_couples text;
begin
  if tg_op = 'UPDATE' then
    changed_couples := format('select %1$I from old_rows union select %1$I from new_rows', tg_argv[1]);
  else
    changed_couples := format('select distinct %I from changed_rows', tg_argv[1]);
  end if;
  for couple in execute changed_couples loop
    perform realtime.send('{}'::jsonb, tg_argv[0], tg_argv[2] || couple::text, true);
  end loop;
  return null;
end $$;
revoke all on function private.notify_couple_change() from public, anon, authenticated;

do $$
declare
  t text;
  event_name text;
  id_column text;
  topic_prefix text;
begin
  foreach t in array array['trips', 'trip_regions', 'couple_region_overrides', 'couples', 'photos', 'photo_day_shares'] loop
    event_name := case t
      when 'trip_regions' then 'trips'
      when 'couple_region_overrides' then 'overrides'
      when 'couples' then 'couple'
      when 'photo_day_shares' then 'shares'
      else t end;
    id_column := case when t = 'couples' then 'id' else 'couple_id' end;
    topic_prefix := case when t = 'photo_day_shares' then 'couple-shares:' else 'couple:' end;
    execute format('create trigger notify_insert after insert on public.%I
      referencing new table as changed_rows for each statement
      execute function private.notify_couple_change(%L, %L, %L)', t, event_name, id_column, topic_prefix);
    execute format('create trigger notify_delete after delete on public.%I
      referencing old table as changed_rows for each statement
      execute function private.notify_couple_change(%L, %L, %L)', t, event_name, id_column, topic_prefix);
    execute format('create trigger notify_update after update on public.%I
      referencing old table as old_rows new table as new_rows for each statement
      execute function private.notify_couple_change(%L, %L, %L)', t, event_name, id_column, topic_prefix);
  end loop;
end $$;

create function private.notify_active_couple_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform realtime.send('{}'::jsonb, 'membership', 'user:' || new.id::text, true);
  return null;
end $$;
revoke all on function private.notify_active_couple_change() from public, anon, authenticated;
create trigger notify_active_couple_change after update of active_couple_id on public.users
  for each row when (old.active_couple_id is distinct from new.active_couple_id)
  execute function private.notify_active_couple_change();
