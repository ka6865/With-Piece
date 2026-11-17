// 하루 1회 정리 작업(설계 8.3, 14.1). pg_cron이 service role 키로 호출한다.
// 1) 유예가 끝난 계정: DB 함수가 커플 기록을 지우고 돌려준 사진 파일을 지운 뒤 계정을 지운다
// 2) photos 행이 없는 24시간 넘은 사진 파일을 지운다
// 3) 만료된 초대와 오래된 초대 시도 기록을 지운다
// DB를 먼저 지우므로 파일 삭제가 실패해도 다음 날 2)가 메운다.
import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "photos";
const BATCH = 500;

Deno.serve(async (req) => {
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  // 새 비밀 키는 JWT가 아니므로 플랫폼 JWT 검사 대신 직접 비교한다(config.toml verify_jwt = false)
  if (req.headers.get("Authorization") !== `Bearer ${serviceKey}`) {
    return new Response("unauthorized", { status: 401 });
  }
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);

  const removeAll = async (paths: string[]) => {
    for (let i = 0; i < paths.length; i += BATCH) {
      const { error } = await supabase.storage.from(BUCKET).remove(paths.slice(i, i + BATCH));
      if (error) throw error;
    }
  };

  const purged = await supabase.rpc("purge_expired_users");
  if (purged.error) throw purged.error;
  for (const row of purged.data as { user_id: string; object_paths: string[] }[]) {
    await removeAll(row.object_paths);
    const { error } = await supabase.auth.admin.deleteUser(row.user_id);
    if (error) throw error;
  }

  const orphans = await supabase.rpc("orphan_photo_paths");
  if (orphans.error) throw orphans.error;
  await removeAll(orphans.data as string[]);

  const stale = await supabase.rpc("cleanup_stale");
  if (stale.error) throw stale.error;

  return Response.json({
    purgedUsers: purged.data.length,
    orphanFiles: orphans.data.length,
  });
});
