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
bash supabase/tests/photo_day_shares_race.sh
flutter test                  # 스택이 떠 있으면 test/supabase 통합 테스트도 돈다
flutter run --dart-define-from-file=env/local.json
```

Kakao 로그인을 로컬에서 쓰려면 `supabase/.env`에 `SUPABASE_AUTH_EXTERNAL_KAKAO_CLIENT_ID`와 `SUPABASE_AUTH_EXTERNAL_KAKAO_SECRET`을 넣는다. 이 파일은 커밋하지 않는다. 쓰지 않을 때는 `supabase stop`으로 끈다.

## 출시 빌드

```bash
flutter build ios --release --dart-define-from-file=env/prod.json
```

`env/prod.json`(gitignore)에 출시용 프로젝트의 `SUPABASE_URL`과 `SUPABASE_PUBLISHABLE_KEY`를 둔다. 오류 진단을 켜려면 `SENTRY_DSN`과 `SENTRY_ENVIRONMENT`를 추가한다.
`DEV_SOLO`를 넣지 않는다. 넣지 않으면 초대 코드 BGMS가 일반 코드로 처리된다(설계 13.1).
개발용 빌드는 `env/cloud.json`(개발 프로젝트, `DEV_SOLO`=true)을 쓴다.

## 비교할 기록 선택

미승인 사진 스캔 결과는 폰에만 저장한다. 비교를 승인한 날짜·지역·장수만 서버에 저장하며, 기기를 바꿔도 기존 승인은 유지된다.
최신화 탭의 **최신화하기**로 사진첩을 다시 읽은 뒤 **비교할 기록 선택**에서 날짜·지역을 고르고 저장하면, 두 사람이 각각 승인한 기록의 교집합으로 여행 후보를 만든다. 승인한 날짜·지역은 상대가 알아낼 수 있으므로 공개해도 되는 기록만 고른다. 승인 범위는 현재 커플에만 적용된다. 상대가 승인을 바꾸면 커플 전용 Realtime 알림을 받아 교집합을 다시 읽는다. 지도 안내를 닫거나, 안내가 열려 있을 때 직접 새로 확인할 수 있다. 다른 기기에서 승인한 기록도 선택 화면에 표시하며, 저장은 내가 바꾼 항목에만 적용한다.

설정은 커플이 없어도 열 수 있다. 사귄 날은 계정 설정에서 수정한다. 연결 전에는 계정 설정에서 **전체 다시 스캔**을 할 수 있다.
이전 버전에서 업로드한 기록은 새 버전에서 다시 승인해야 비교에 사용된다.

## 정리 작업(daily-cleanup)

`supabase/functions/daily-cleanup`은 유예가 끝난 계정 삭제, 고아 사진 파일 정리, 만료 초대 정리를 한다.
정리 작업은 만료된 요청을 잠가 처리 시작을 기록한 뒤 사진 파일 → 공동 기록 → Auth 계정 순서로 지운다. 실패하면 다음 실행에서 재시도한다. 작업은 마이그레이션이 매일 03:00 KST로 등록한다.

정리 함수를 출시 프로젝트에 배포한다.

```bash
supabase functions deploy daily-cleanup --project-ref <ref>
```

해당 환경의 SQL Editor에서 첫 배포 때 Vault 값을 등록한다. 기존 값이 있으면 해당 비밀을 갱신한다.

```sql
select vault.create_secret(
  encode(extensions.gen_random_bytes(32), 'hex'), 'daily_cleanup_token'
);
select vault.create_secret(
  'https://<ref>.supabase.co/functions/v1/daily-cleanup', 'daily_cleanup_url'
);
```

다음 예약 실행 뒤 함수 로그와 스케줄러의 HTTP 응답에서 성공 여부를 확인한다. 토큰과 함수 주소가 준비되면 예약된 작업이 호출을 시작한다.

출시 환경과 관계 변경·수익화의 검증 기준은 [출시와 후속 버전 검토](docs/reviews/release-readiness.md)에 있다. 앱 전체 리뷰와 항목별 후속 작업은 [앱 리뷰 기록](docs/reviews/2026-11-24-app-review.md)에 있다.

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

정리 함수의 순서·실패 전파 테스트는 Node 26 이상에서 `node --test supabase/functions/daily-cleanup/index_test.mjs`로 실행한다. Supabase 호출은 대체하며 실제 클라우드 데이터를 지우지 않는다.
