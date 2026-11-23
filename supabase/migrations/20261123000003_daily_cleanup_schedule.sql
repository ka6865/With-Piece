-- 정리 작업(daily-cleanup) 하루 1회 예약(설계 8.3). pg_cron이 pg_net으로 함수를 부른다.
-- 서비스 키를 DB에 넣지 않으려고, 환경마다 DB가 만든 무작위 토큰을 Vault에 두고 함수가
-- 이 RPC로 확인한다. 토큰과 함수 URL은 마이그레이션이 아니라 환경별로 Vault에 넣는다:
--   select vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'daily_cleanup_token');
--   select vault.create_secret('https://<ref>.supabase.co/functions/v1/daily-cleanup', 'daily_cleanup_url');
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

create function public.cleanup_token_valid(p_token text) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(p_token <> '' and exists (
    select 1 from vault.decrypted_secrets
    where name = 'daily_cleanup_token' and decrypted_secret = p_token
  ), false);
$$;
revoke execute on function public.cleanup_token_valid(text) from public, anon, authenticated;
grant execute on function public.cleanup_token_valid(text) to service_role;

-- 한국 시간 새벽 3시. Vault에 토큰이 없는 환경(로컬)에서는 아무것도 보내지 않는다
select cron.schedule('daily-cleanup', '0 18 * * *', $job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name = 'daily_cleanup_url'),
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || (
        select decrypted_secret from vault.decrypted_secrets where name = 'daily_cleanup_token')
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 120000
  )
  where exists (select 1 from vault.decrypted_secrets where name = 'daily_cleanup_url')
    and exists (select 1 from vault.decrypted_secrets where name = 'daily_cleanup_token');
$job$);
