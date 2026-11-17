import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { stripTypeScriptTypes } from 'node:module';
import test from 'node:test';
import vm from 'node:vm';

// 실제 엔트리포인트를 실행하고 외부 Supabase 호출만 대체한다.
const source = stripTypeScriptTypes(await readFile(new URL('./index.ts', import.meta.url), 'utf8'))
  .replace(/^import .*createClient.*;\s*$/m, '');

function handler({ storageFails = false, authFails = false } = {}) {
  const calls = [];
  let serve;
  const client = {
    rpc: async (name) => {
      calls.push(name);
      return { data: name === 'purge_expired_users'
        ? [{ user_id: 'u1', object_paths: ['c1/t1/full/p.heic'] }]
        : name === 'orphan_photo_paths' ? [] : null, error: null };
    },
    storage: { from: () => ({ remove: async () => {
      calls.push('storage');
      return { error: storageFails ? new Error('storage unavailable') : null };
    } }) },
    auth: { admin: { deleteUser: async () => {
      calls.push('auth');
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
  assert.deepEqual(h.calls, ['purge_expired_users', 'storage', 'finalize_expired_user',
    'auth', 'orphan_photo_paths', 'cleanup_stale']);
});
test('파일 삭제가 실패하면 관계와 계정을 지우지 않는다', async () => {
  const h = handler({ storageFails: true });
  await assert.rejects(h.run(), /storage unavailable/);
  assert.deepEqual(h.calls, ['purge_expired_users', 'storage']);
});
test('Auth 삭제 실패는 성공으로 숨기지 않는다', async () => {
  const h = handler({ authFails: true });
  await assert.rejects(h.run(), /auth unavailable/);
  assert.deepEqual(h.calls, ['purge_expired_users', 'storage', 'finalize_expired_user', 'auth']);
});
