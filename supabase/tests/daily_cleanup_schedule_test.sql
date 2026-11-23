begin;
select plan(5);

select is(
  (select schedule from cron.job where jobname = 'daily-cleanup'), '0 18 * * *',
  '정리 작업은 매일 18:00 UTC(한국 03:00)에 돈다');

select vault.create_secret('test-token', 'daily_cleanup_token');
set local role service_role;
select is(public.cleanup_token_valid('test-token'), true, 'Vault 토큰이면 통과');
select is(public.cleanup_token_valid('wrong'), false, '다른 값이면 거부');
select is(public.cleanup_token_valid(''), false, '빈 값이면 거부');
reset role;

set local role authenticated;
select throws_ok($$ select public.cleanup_token_valid('test-token') $$, '42501', null,
  '로그인 사용자는 토큰을 맞춰 볼 수 없다');

select * from finish();
rollback;
