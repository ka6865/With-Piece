# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

프로젝트 규칙의 원본은 `AGENTS.md`다. 여기에는 그 파일에 없는 것만 적는다.

@AGENTS.md

## 현재 상태

1~3단계(지도, Supabase 기반, MVP 기능)가 끝났다. 3단계의 두 기기 실사용 확인은 4단계 TestFlight로 미뤘다. 지금은 커플 디자인 개편(`docs/superpowers/specs/2026-11-19-커플-디자인-design.md`, ①~⑤ 단계별 PR)을 진행하고, 그 뒤 4단계 출시 준비(방명록·사진 댓글 포함)다. `docs/superpowers/`는 gitignore 대상이라 로컬에만 있다.

## 명령

```bash
supabase start -x studio,imgproxy,vector,logflare,edge-runtime,supavisor   # 로컬 스택(Docker)
supabase db reset --debug                      # 마이그레이션 재적용. --debug 없이 끝에 502가 나도 적용은 된다
# db reset 뒤 Storage 업로드가 42P10(infer_arbiter_indexes)으로 실패하면 Storage 내부 마이그레이션이
# 덜 끝난 것이다. supabase stop 후 다시 start하면 풀린다
supabase test db                               # pgTAP(supabase/tests/*.sql)
bash supabase/tests/join_race.sh               # 초대 동시 수락 경합
flutter test                                   # 전체. test/supabase는 스택에 닿지 않으면 건너뛴다
flutter test test/features/map/painter/region_hit_tester_test.dart   # 파일 하나
flutter test --plain-name "229"                # 이름으로 테스트 하나
dart analyze                                   # flutter analyze는 한글 경로에서 죽는다(AGENTS.md 5장)
dart run tool/build_map_assets.dart            # TopoJSON -> assets/map/*.json
dart run tool/build_regions_sql.dart > supabase/migrations/20261117000002_regions.sql
flutter run --dart-define-from-file=env/local.json   # 접속 정보 없이 실행하면 시작 시 멈춘다
```

개발 전용 테스트 상대: `DEV_SOLO=true` 빌드에서 초대 코드 `BGMS`로 혼자 커플을 만든다. 서버 쪽은 마이그레이션이 아닌 `supabase/dev/solo_partner.sql`이며 출시용 프로젝트·빌드에 절대 넣지 않는다(설계 13.1).

접속 정보와 키는 커밋하지 않는다. `env/local.json`(로컬 스택), `env/cloud.json`(무료 조직 개발 프로젝트), `supabase/.env`(Kakao 키)는 gitignore 대상이고 `env/example.json`만 커밋한다. 클라우드 Auth 설정은 `supabase config push`로 올리지 않는다. 로컬 기본값(이메일 확인 끔 등)이 함께 덮어써진다. 대시보드에서 바꾼다.

실기기 측정은 `integration_test/*_main.dart` 진입점을 릴리즈로 빌드해 `xcrun devicectl device process launch --console`로 표준 출력을 받는다. 무선 연결 기기에서 `flutter drive --profile`은 앱이 뜨지 않는다. 빌드가 성공했을 때만 설치한다. 실패해도 이전 산출물이 남아 있어 엉뚱한 앱이 설치된다.

`tools/`의 검증 스크립트 입력 파일은 저장소에 없다. 원본은 `github.com/southkorea/southkorea-maps`의 `kostat/2018/json/`이다.
- `verify_region_pieces.py`, `verify_hittest.py`: 상세 GeoJSON(`skorea-municipalities-2018-geo.json`, 약 18MB)을 받는다
- `topo_to_flat.py`: `topo-simple` TopoJSON을 받는다
- `build_map_assets_ref.py`: Dart 전처리(`tool/build_map_assets.dart`)의 참조 구현이다. 산출물 스키마와 값이 다르면 이 스크립트를 기준으로 본다

1단계 계획은 `topo-simple` 원본 두 개를 `tool/map_source/`에 고정해 커밋한다.

## 큰 그림

- 지도 폴리곤은 DB가 아니라 번들 애셋(`assets/map/regions_v1.json`, `provinces_v1.json`)이 단일 원본이다. 진행률의 분모도 애셋에서 계산하고, DB view는 방문한 조각만 돌려준다.
- 핵심 기능은 갤러리 자동 채우기다. 각 기기가 사진 위치를 조각 코드로 바꾸고, 서버는 두 사람의 (날짜, 조각) 목록의 교집합만 `couple_matched_days()` RPC로 돌려준다. 생활권 분류와 여행 후보 묶기는 클라이언트의 순수 Dart 함수다(설계 문서 5장).
- 사진 위치의 조각 판정은 지도 탭과 같은 판정 로직을 경위도 공간에 적용한다. 판정 로직을 고치면 탭과 스캔 양쪽 테스트를 함께 본다.
- 사진은 Supabase Storage private 버킷이고, 권한은 `storage.objects` RLS가 경로 첫 세그먼트(`couple_id`)로 판정한다. 별도 URL 발급 함수가 없다.
