-- 내 photo_days를 주어진 목록과 같게 맞춘다(설계 5.2). 빠진 행 삭제와 upsert를
-- 한 트랜잭션으로 해 중간에 끊겨도 반쯤 반영된 상태가 남지 않는다.
-- security invoker라 RLS(user_id = auth.uid())가 그대로 적용된다
create function public.replace_photo_days(p_rows jsonb) returns void
language sql security invoker set search_path = '' as $$
  delete from public.photo_days d
  where d.user_id = (select auth.uid())
    and not exists (
      select 1 from jsonb_to_recordset(p_rows) as r(day date, region_id text, photo_count int)
      where r.day = d.day and r.region_id = d.region_id
    );
  insert into public.photo_days (user_id, day, region_id, photo_count)
  select (select auth.uid()), r.day, r.region_id, r.photo_count
  from jsonb_to_recordset(p_rows) as r(day date, region_id text, photo_count int)
  on conflict (user_id, day, region_id) do update set photo_count = excluded.photo_count;
$$;

revoke execute on function public.replace_photo_days(jsonb) from public, anon;
grant execute on function public.replace_photo_days(jsonb) to authenticated;
