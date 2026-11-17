import 'package:flutter_riverpod/flutter_riverpod.dart';

// 개발 빌드에서만 켠다(--dart-define-from-file=env/cloud.json 의 DEV_SOLO).
// 켜지면 초대 코드 BGMS로 테스트 상대와 연결해 혼자 테스트할 수 있다.
// 서버 함수(supabase/dev/solo_partner.sql)도 개발 프로젝트에만 있다
const devSoloCode = 'BGMS';

final devSoloEnabledProvider = Provider<bool>(
  (ref) => const bool.fromEnvironment('DEV_SOLO'),
);
