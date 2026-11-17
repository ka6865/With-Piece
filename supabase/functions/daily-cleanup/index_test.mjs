import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

// 실제 엔트리포인트를 실행하고 외부 Supabase 호출만 대체한다.
const source = stripTypeScriptTypes(await readFile(new URL('./index.ts', import.meta.url), 'utf8'))
  .replace(/^import .*createClient.*;\s*$/m, '');

function handler({ storageFails = false, authFails = false, finalizeFails = false,
  staleFails = false, accounts = [{ user_id: 'u1', object_paths: ['c1/t1/full/p.heic'] }] } = {}) {
  const calls = [];
  let serve;
  const client = {
    rpc: async (name, args) => {
      calls.push(name === 'finalize_expired_user' ? `finalize:${args.p_user_id}` : name);
      return { data: name === 'purge_expired_users'
        ? accounts
        : name === 'orphan_photo_paths' ? ['orphan.heic'] : null,
      error: name === 'finalize_expired_user' && finalizeFails
        ? new Error('finalize unavailable')
        : name === 'cleanup_stale' && staleFails ? new Error('stale cleanup unavailable') : null };
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
  });
  return { calls, run: (authorized = true) => serve(new Request('http://local', {
    headers: authorized ? { Authorization: 'Bearer secret' } : {},
  })) };
}

test('서비스 키가 없으면 데이터에 접근하지 않는다', async () => {
  const h = handler();
  assert.equal((await h.run(false)).status, 401);
  assert.deepEqual(h.calls, []);
});
test('파일 삭제 후 DB 정리를 확정하고 Auth를 삭제한다', async () => {
  const h = handler();
  assert.equal((await h.run()).status, 200);
  assert.deepEqual(h.calls, ['purge_expired_users', 'storage:c1/t1/full/p.heic', 'finalize:u1',
    'auth:u1', 'orphan_photo_paths', 'storage:orphan.heic', 'cleanup_stale']);
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
