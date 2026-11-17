#!/usr/bin/env bash
# 같은 초대 코드를 두 사람이 동시에 수락하면 하나만 성공하는지 확인한다(설계 9.3).
# 로컬 스택에 대고 실행하며, 만든 행은 끝에서 지운다.
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
X=00000000-0000-0000-0000-00000000aa01
Y=00000000-0000-0000-0000-00000000aa02
Z=00000000-0000-0000-0000-00000000aa03
CODE=RACE234567

cleanup() {
  psql "$DB_URL" -qtA -v ON_ERROR_STOP=1 <<SQL >/dev/null
update public.users set active_couple_id = null where id in ('$X', '$Y', '$Z');
delete from public.couples where user_a_id in ('$X', '$Y', '$Z') or user_b_id in ('$X', '$Y', '$Z');
delete from auth.users where id in ('$X', '$Y', '$Z');
SQL
}
trap cleanup EXIT
cleanup

psql "$DB_URL" -qtA -v ON_ERROR_STOP=1 <<SQL >/dev/null
insert into auth.users (id) values ('$X'), ('$Y'), ('$Z');
insert into public.couple_invites (inviter_id, code, expires_at) values ('$X', '$CODE', now() + interval '1 day');
SQL

# 수락 직후 1초 동안 트랜잭션을 열어 두어 두 세션이 반드시 겹치게 한다
join_as() {
  psql "$DB_URL" -qtA -v ON_ERROR_STOP=1 <<SQL
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true) \g /dev/null
select public.join_couple('$CODE');
select pg_sleep(1) \g /dev/null
commit;
SQL
}

join_as "$Y" > "${TMPDIR:-/tmp}/join_race_y" &
join_as "$Z" > "${TMPDIR:-/tmp}/join_race_z" &
wait

results="$(cat "${TMPDIR:-/tmp}/join_race_y" "${TMPDIR:-/tmp}/join_race_z" | grep -vE '^(BEGIN|COMMIT|SET)?$' | sort | tr '\n' ' ')"
couples="$(psql "$DB_URL" -qtA -c "select count(*) from public.couples where user_a_id = '$X'")"
echo "결과: $results / 커플 수: $couples"

oks="$(echo "$results" | tr ' ' '\n' | grep -c '^ok$' || true)"
if [[ "$oks" == 1 && "$couples" == 1 ]]; then
  echo "통과: 하나만 성공"
else
  echo "실패: 성공 $oks개, 커플 $couples행" >&2
  exit 1
fi
