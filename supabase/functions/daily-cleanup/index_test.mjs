import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

// 실제 엔트리포인트를 실행하고 외부 Supabase 호출만 대체한다.
const source = stripTypeScriptTypes(await readFile(new URL('./index.ts', import.meta.url), 'utf8'))
  .replace(/^import .*createClient.*;\s*$/m, '');

function handler({ storageFails = false, authFails = false, finalizeFails = false,
  staleFails = false, purgeFails = false, orphanFails = false,
  accounts = [{ user_id: 'u1', object_paths: ['c1/t1/full/p.heic'] }] } = {}) {
  const calls = [];
  const logs = [];
  let serve;
  const client = {
    rpc: async (name, args) => {
      calls.push(name === 'finalize_expired_user' ? `finalize:${args.p_user_id}` : name);
      if (name === 'cleanup_token_valid') return { data: args.p_token === 'vault-token', error: null };
      return { data: name === 'purge_expired_users'
        ? accounts
        : name === 'orphan_photo_paths' ? ['orphan.heic'] : null,
      error: name === 'finalize_expired_user' && finalizeFails
        ? new Error('finalize unavailable')
        : name === 'cleanup_stale' && staleFails ? new Error('stale cleanup unavailable')
        : name === 'purge_expired_users' && purgeFails
          ? { message: typeof purgeFails === 'string' ? purgeFails : 'purge unavailable', details: 'secret' }
        : name === 'orphan_photo_paths' && orphanFails
          ? { message: 'orphan unavailable', details: 'secret' } : null };
    },
    storage: { from: () => ({ remove: async (paths) => {
      calls.push(`storage:${paths[0]}`);
      return { error: storageFails === true || storageFails.includes?.(paths[0])
        ? new Error('storage unavailable') : null };
    } }) },
    auth: { admin: { deleteUser: async (userId) => {
      calls.push(`auth:${userId}`);
      return { error: authFails ? new Error('auth unavailable') : null };
    } } },
  };
  vm.runInNewContext(source, {
    createClient: () => client,
    Deno: { env: { get: (name) => name === 'SUPABASE_SERVICE_ROLE_KEY' ? 'secret' : 'http://local' },
      serve: (fn) => { serve = fn; } },
    Response,
    console: { error: (line) => logs.push(JSON.parse(line)) },
  });
  // true면 서비스 키, 문자열이면 그 토큰, false면 헤더 없이 부른다
  return { calls, logs, run: (authorized = true) => serve(new Request('http://local', {
    headers: authorized === false ? {}
      : { Authorization: `Bearer ${authorized === true ? 'secret' : authorized}` },
  })) };
}

test('서비스 키가 없으면 데이터에 접근하지 않는다', async () => {
  const h = handler();
  assert.equal((await h.run(false)).status, 401);
  assert.deepEqual(h.calls, []);
  assert.deepEqual(h.logs, []);
});
test('일정 작업이 보낸 Vault 토큰이 맞으면 정리한다', async () => {
  const h = handler();
  assert.equal((await h.run('vault-token')).status, 200);
  assert.ok(h.calls.includes('orphan_photo_paths'));
});
test('토큰이 틀리면 토큰 확인 말고는 아무것도 하지 않는다', async () => {
  const h = handler();
  assert.equal((await h.run('wrong')).status, 401);
  assert.deepEqual(h.calls, ['cleanup_token_valid']);
});
test('파일 삭제 후 DB 정리를 확정하고 Auth를 삭제한다', async () => {
  const h = handler();
  assert.equal((await h.run()).status, 200);
  assert.deepEqual(h.calls, ['purge_expired_users', 'storage:c1/t1/full/p.heic', 'finalize:u1',
    'auth:u1', 'orphan_photo_paths', 'storage:orphan.heic', 'cleanup_stale']);
  assert.deepEqual(h.logs, []);
});
test('파일 삭제가 실패하면 관계와 계정을 지우지 않는다', async () => {
  const h = handler({ storageFails: true });
  assert.notEqual((await h.run()).status, 200);
  assert.deepEqual(h.calls, ['purge_expired_users', 'storage:c1/t1/full/p.heic', 'orphan_photo_paths',
    'storage:orphan.heic', 'cleanup_stale']);
});
test('Auth 삭제 실패는 성공으로 숨기지 않는다', async () => {
  const h = handler({ authFails: true });
  assert.notEqual((await h.run()).status, 200);
  assert.deepEqual(h.calls, ['purge_expired_users', 'storage:c1/t1/full/p.heic', 'finalize:u1', 'auth:u1',
    'orphan_photo_paths', 'storage:orphan.heic', 'cleanup_stale']);
});
test('DB 정리 확정 실패 뒤 Auth 삭제를 건너뛰고 나머지 정리를 시도한다', async () => {
  const h = handler({ finalizeFails: true });
  assert.notEqual((await h.run()).status, 200);
  assert.deepEqual(h.calls, ['purge_expired_users', 'storage:c1/t1/full/p.heic',
    'finalize:u1', 'orphan_photo_paths', 'storage:orphan.heic', 'cleanup_stale']);
});
test('stale 정리 실패는 안전한 단계 이름으로 응답한다', async () => {
  const h = handler({ staleFails: true });
  const response = await h.run();
  assert.equal(response.status, 500);
  assert.deepEqual((await response.json()).failedPhases, ['stale_cleanup']);
});

test('한 계정의 실패 뒤에도 다음 계정과 orphan 및 stale 정리를 시도한다', async () => {
  const h = handler({ storageFails: ['c1/t1/full/p.heic'], accounts: [
    { user_id: 'u1', object_paths: ['c1/t1/full/p.heic'] },
    { user_id: 'u2', object_paths: ['c2/t2/full/p.heic'] },
  ] });
  const response = await h.run();
  assert.equal(response.status, 500);
  const result = await response.json();
  assert.deepEqual(result.expiredAccounts, { succeeded: 1, failed: 1 });
  assert.deepEqual(result.failedPhases, []);
  assert.deepEqual(h.calls, ['purge_expired_users', 'storage:c1/t1/full/p.heic',
    'storage:c2/t2/full/p.heic', 'finalize:u2', 'auth:u2', 'orphan_photo_paths',
    'storage:orphan.heic', 'cleanup_stale']);
  assert.doesNotMatch(JSON.stringify(result), /u1|u2|unavailable|c1\/|c2\//);
});

for (const [option, phase, message] of [
  ['storageFails', 'expired_storage', 'storage unavailable'],
  ['finalizeFails', 'expired_finalize', 'finalize unavailable'],
  ['authFails', 'expired_auth', 'auth unavailable'],
]) {
  test(`계정별 ${phase} 실패는 사용자와 메시지를 구조화 로그에 남긴다`, async () => {
    const h = handler({ [option]: true });
    const response = await h.run();
    assert.equal(response.status, 500);
    assert.deepEqual(h.logs[0], { event: 'cleanup_failed', phase, userId: 'u1', message });
    assert.doesNotMatch(JSON.stringify(h.logs), /secret|c1\/|details/);
    assert.doesNotMatch(await response.text(), /u1|unavailable|secret/);
    assert.equal(h.calls.at(-1), 'cleanup_stale');
  });
}

test('배치 RPC와 orphan 및 stale 실패를 단계와 메시지로 기록하고 계속 진행한다', async () => {
  const h = handler({ purgeFails: true, orphanFails: true, staleFails: true });
  const response = await h.run();
  assert.equal(response.status, 500);
  assert.deepEqual(h.logs, [
    { event: 'cleanup_failed', phase: 'expired_accounts', message: 'purge unavailable' },
    { event: 'cleanup_failed', phase: 'orphan_cleanup', message: 'orphan unavailable' },
    { event: 'cleanup_failed', phase: 'stale_cleanup', message: 'stale cleanup unavailable' },
  ]);
  assert.deepEqual(h.calls, ['purge_expired_users', 'orphan_photo_paths', 'cleanup_stale']);
  assert.deepEqual(await response.json(), {
    error: 'cleanup_failed', expiredAccounts: { succeeded: 0, failed: 0 },
    failedPhases: ['expired_accounts', 'orphan_cleanup', 'stale_cleanup'],
  });
  assert.doesNotMatch(JSON.stringify(h.logs), /secret|details/);
});

test('오류 메시지에 서비스 키가 포함돼도 로그에는 가린다', async () => {
  const h = handler({ purgeFails: 'request failed: Bearer secret' });
  assert.equal((await h.run()).status, 500);
  assert.equal(h.logs[0].message, 'request failed: Bearer [REDACTED]');
  assert.doesNotMatch(JSON.stringify(h.logs), /secret/);
});
