begin;
select plan(2);

-- 전체 교체는 승인 보존과 잠금을 우회하므로 남기지 않는다(sync_photo_days를 쓴다)
select hasnt_function('public', 'replace_photo_days', array['jsonb'], '원본 전체 교체 RPC가 없다');
select hasnt_function('public', 'replace_photo_day_shares', array['uuid', 'jsonb'], '승인 전체 교체 RPC가 없다');

select * from finish();
rollback;
