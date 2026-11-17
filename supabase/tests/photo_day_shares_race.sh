#!/usr/bin/env bash
# 같은 계정에서 두 승인 저장이 겹쳐도 두 번째 목록으로 교체되는지 확인한다.
set -euo pipefail

db=(psql -X -qAt -v ON_ERROR_STOP=1 postgresql://postgres:postgres@127.0.0.1:54322/postgres)
IFS='|' read -r owner partner couple < <("${db[@]}" -c 'select gen_random_uuid(), gen_random_uuid(), gen_random_uuid()')
scratch="$(mktemp -d)"
second_app="photo-shares-${couple}"

cleanup() {
  touch "$scratch/commit"
  wait
  "${db[@]}" <<SQL
update public.users set active_couple_id = null where active_couple_id = '$couple';
delete from public.couples where id = '$couple';
delete from auth.users where id in ('$owner', '$partner');
SQL
  rm -rf "$scratch"
}
trap cleanup EXIT

"${db[@]}" <<SQL
begin;
insert into auth.users (id) values ('$owner'), ('$partner');
insert into public.couples (id, user_a_id, user_b_id, started_on)
values ('$couple', '$owner', '$partner', '2026-01-01');
update public.users set active_couple_id = '$couple' where id in ('$owner', '$partner');
insert into public.photo_days values
  ('$owner', '2026-01-02', '11010', 1),
  ('$owner', '2026-01-02', '32060', 1),
  ('$owner', '2026-01-02', '32400', 1);
insert into public.photo_day_shares values ('$couple', '$owner', '2026-01-02', '11010');
commit;
SQL

save_sql() {
  cat <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"$owner","role":"authenticated"}', true) \g /dev/null
select public.replace_photo_day_shares('$couple', '[{"day":"2026-01-02","region_id":"$1"}]');
SQL
}

{
  save_sql 32060
  echo "\! touch '$scratch/ready'; for i in \$(seq 1 200); do test -e '$scratch/commit' && break; sleep 0.05; done"
  echo 'commit;'
} | "${db[@]}" >/dev/null &
first=$!
for i in $(seq 1 200); do
  [[ -e "$scratch/ready" ]] && break
  sleep 0.05
done
[[ -e "$scratch/ready" ]]

{ save_sql 32400; echo 'commit;'; } | PGAPPNAME="$second_app" "${db[@]}" >/dev/null &
second=$!
blocked=f
for i in $(seq 1 100); do
  blocked="$("${db[@]}" -c "select exists(select 1 from pg_stat_activity where application_name = '$second_app' and wait_event_type = 'Lock')")"
  [[ "$blocked" == t ]] && break
  sleep 0.05
done
[[ "$blocked" == t ]]
touch "$scratch/commit"
wait "$first"
wait "$second"

actual="$("${db[@]}" -c "select string_agg(region_id, ',' order by region_id) from public.photo_day_shares where couple_id = '$couple' and user_id = '$owner'")"
if [[ "$actual" != 32400 ]]; then
  echo "실패: 마지막 저장은 32400만 선택했으나 서버에는 $actual 이 남았다." >&2
  exit 1
fi
echo "통과: 마지막 승인 목록만 남았다."
