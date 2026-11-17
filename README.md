# 우리들의 조각

커플이 함께 다녀온 대한민국 시·군·구를 퍼즐 조각으로 채우는 추억 기록 앱.
설계는 `docs/superpowers/specs/2026-11-17-우리만의조각-design.md`, 작업 규칙은 `AGENTS.md`에 있다.

## 지도 애셋 재현

```text
dart run tool/build_map_assets.dart
flutter test
dart analyze

regions_v1.json: 229조각, 79,868점, 1,680,480바이트
provinces_v1.json: 17시도, 30,623점, 637,805바이트
```

`flutter analyze`는 저장소 경로의 한글 때문에 분석 서버가 죽어 `dart analyze`로 대신한다.
원본과 해시는 `tool/map_source/README.md`에 있다.

## 로컬 Supabase

Docker Desktop을 켠 뒤:

```bash
supabase start -x studio,imgproxy,vector,logflare,edge-runtime,supavisor
supabase status -o env        # API_URL, PUBLISHABLE_KEY를 env/local.json에 넣는다(env/example.json 형식)
supabase db reset --debug     # 마이그레이션과 regions 기준 데이터 적용
supabase test db              # RLS·RPC pgTAP
bash supabase/tests/join_race.sh
flutter test                  # 스택이 떠 있으면 test/supabase 통합 테스트도 돈다
flutter run --dart-define-from-file=env/local.json
```

Kakao 로그인을 로컬에서 쓰려면 `supabase/.env`에 `SUPABASE_AUTH_EXTERNAL_KAKAO_CLIENT_ID`와 `SUPABASE_AUTH_EXTERNAL_KAKAO_SECRET`을 넣는다. 이 파일은 커밋하지 않는다. 쓰지 않을 때는 `supabase stop`으로 끈다.

## 출시 빌드

```bash
flutter build ios --release --dart-define-from-file=env/prod.json
```

`env/prod.json`(gitignore)은 출시용 프로젝트의 `SUPABASE_URL`과 `SUPABASE_PUBLISHABLE_KEY`만 둔다.
`DEV_SOLO`를 넣지 않는다. 넣지 않으면 초대 코드 BGMS가 일반 코드로 처리된다(설계 13.1).
개발용 빌드는 `env/cloud.json`(개발 프로젝트, `DEV_SOLO`=true)을 쓴다.

## 정리 작업(daily-cleanup)

`supabase/functions/daily-cleanup`은 유예가 끝난 계정 삭제, 고아 사진 파일 정리, 만료 초대 정리를 한다.
service role 키로만 호출된다. 클라우드에 배포한 뒤 서비스 키를 Vault에 넣고 하루 1회 일정을 건다.

```bash
supabase functions deploy daily-cleanup --project-ref <ref>
```

```sql
select vault.create_secret('<service role key>', 'service_role_key');
select cron.schedule(
  'daily-cleanup',
  '0 18 * * *',  -- 매일 03:00 KST
  $$ select net.http_post(
       url := 'https://<ref>.supabase.co/functions/v1/daily-cleanup',
       headers := jsonb_build_object('Authorization', 'Bearer ' ||
         (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key'))
     ) $$
);
```

## 원본 기준 검증

`tools/`의 Python 스크립트는 설계 문서의 확정값을 원본에서 다시 계산한다. 상세 GeoJSON은
저장소에 넣지 않으므로 받아서 쓴다.

```bash
curl -L --fail https://raw.githubusercontent.com/southkorea/southkorea-maps/master/kostat/2018/json/skorea-municipalities-2018-geo.json -o geo.json
python3 tools/verify_region_pieces.py geo.json     # 조각 229, 시도별 분모
python3 tools/verify_hittest.py geo.json           # 본토 228개 내부점 판정 실패 0
python3 tools/topo_to_flat.py tool/map_source/skorea-municipalities-2018-topo-simple.json flat.json
python3 tools/build_adjacency.py flat.json adjacency_v1.json   # 인접 584, 보완 후 590
```

2026-11-17 기준 상세 GeoJSON의 SHA-256은
`14c174c880d45c3c62aa97d9d4fc0d8605f0999560a4b70096567a8eb77f2ca9`이고 위 값이 모두 재현된다.
