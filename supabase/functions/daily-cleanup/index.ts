// 하루 1회 정리 작업(설계 8.3, 14.1). pg_cron이 service role 키로 호출한다.
// 1) 유예가 끝난 계정: 정리 시작을 기록하고 Storage 파일, 커플 기록, 계정을 순서대로 지운다
// 2) photos 행이 없는 24시간 넘은 사진 파일을 지운다
// 3) 만료된 초대와 오래된 초대 시도 기록을 지운다
// Storage 삭제가 실패해도 DB 메타데이터와 경로를 보존해 다음 실행에서 재시도한다.
import { createClient } from "jsr:@supabase/supabase-js@2";

const BUCKET = "photos";
const BATCH = 500;

Deno.serve(async (req) => {
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, serviceKey);
  // 새 비밀 키는 JWT가 아니므로 플랫폼 JWT 검사 대신 직접 비교한다(config.toml verify_jwt = false).
  // pg_cron은 서비스 키 대신 DB가 만든 Vault 토큰을 보내므로 서비스 키가 DB 밖으로 나가지 않는다
  const header = req.headers.get("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  const authorized = token !== "" && (token === serviceKey ||
    (await supabase.rpc("cleanup_token_valid", { p_token: token })).data === true);
  if (!authorized) {
    return new Response("unauthorized", { status: 401 });
  }

  const logFailure = (phase: string, error: unknown, userId?: string) => {
    const message = String(error && typeof error === "object" && "message" in error
      ? error.message : error);
    console.error(JSON.stringify({
      event: "cleanup_failed", phase, userId,
      message: message.replaceAll(serviceKey, "[REDACTED]"),
    }));
  };

  const removeAll = async (paths: string[]) => {
    for (let i = 0; i < paths.length; i += BATCH) {
      const { error } = await supabase.storage.from(BUCKET).remove(paths.slice(i, i + BATCH));
      if (error) throw error;
    }
  };

  let expiredSucceeded = 0;
  let expiredFailed = 0;
  const failedPhases: string[] = [];
  let orphanFiles = 0;
  try {
    const purged = await supabase.rpc("purge_expired_users");
    if (purged.error) throw purged.error;
    for (const row of purged.data as { user_id: string; object_paths: string[] }[]) {
      let phase = "expired_storage";
      try {
        await removeAll(row.object_paths);
        phase = "expired_finalize";
        const { error: finalizeError } = await supabase.rpc("finalize_expired_user", {
          p_user_id: row.user_id,
        });
        if (finalizeError) throw finalizeError;
        phase = "expired_auth";
        const { error } = await supabase.auth.admin.deleteUser(row.user_id);
        if (error) throw error;
        expiredSucceeded++;
      } catch (error) {
        logFailure(phase, error, row.user_id);
        expiredFailed++;
      }
    }
  } catch (error) {
    logFailure("expired_accounts", error);
    failedPhases.push("expired_accounts");
  }

  try {
    const orphans = await supabase.rpc("orphan_photo_paths");
    if (orphans.error) throw orphans.error;
    orphanFiles = orphans.data.length;
    await removeAll(orphans.data as string[]);
  } catch (error) {
    logFailure("orphan_cleanup", error);
    failedPhases.push("orphan_cleanup");
  }

  try {
    const stale = await supabase.rpc("cleanup_stale");
    if (stale.error) throw stale.error;
  } catch (error) {
    logFailure("stale_cleanup", error);
    failedPhases.push("stale_cleanup");
  }

  if (expiredFailed || failedPhases.length) {
    return Response.json({
      error: "cleanup_failed",
      expiredAccounts: { succeeded: expiredSucceeded, failed: expiredFailed },
      failedPhases,
    }, { status: 500 });
  }
  return Response.json({ purgedUsers: expiredSucceeded, orphanFiles });
});
