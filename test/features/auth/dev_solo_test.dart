import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/core/dev_flags.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/auth/invite_page.dart';

import 'fakes.dart';

Future<FakeCoupleRepository> pump(
  WidgetTester tester, {
  required bool devSolo,
}) async {
  final couple = FakeCoupleRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('me'),
        devSoloEnabledProvider.overrideWithValue(devSolo),
        coupleRepositoryProvider.overrideWithValue(couple),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
      child: const MaterialApp(home: InvitePage()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), ' bgms ');
  await tester.tap(find.text('연결하기'));
  await tester.pumpAndSettle();
  return couple;
}

void main() {
  testWidgets('개발 빌드에서 BGMS를 넣으면 테스트 상대와 연결한다', (tester) async {
    final couple = await pump(tester, devSolo: true);
    expect(couple.devSoloJoins, 1);
    expect(couple.joinedCodes, isEmpty);
  });

  testWidgets('개발 빌드가 아니면 BGMS도 일반 초대 코드다', (tester) async {
    final couple = await pump(tester, devSolo: false);
    expect(couple.devSoloJoins, 0);
    expect(couple.joinedCodes, ['bgms']);
  });

  test('DEV_SOLO 없이 빌드하면 테스트 상대 경로가 꺼져 있다', () {
    // flutter test는 --dart-define 없이 돈다. 출시 빌드와 같은 조건이다
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(devSoloEnabledProvider), isFalse);
  });
}
