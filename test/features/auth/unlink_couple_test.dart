import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/auth/account_links_page.dart';
import 'package:woori_piece/features/auth/auth_state.dart';

import 'fakes.dart';

Future<FakeCoupleRepository> pump(
  WidgetTester tester, {
  required Couple? couple,
}) async {
  final couples = FakeCoupleRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('me'),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        coupleRepositoryProvider.overrideWithValue(couples),
        currentCoupleProvider.overrideWith((ref) async => couple),
      ],
      child: const MaterialApp(home: AccountLinksPage()),
    ),
  );
  await tester.pumpAndSettle();
  return couples;
}

void main() {
  testWidgets('커플 연결 끊기는 결과를 안내하고 확인하면 아카이브한다', (tester) async {
    final couples = await pump(
      tester,
      couple: const Couple(id: 'c1', partnerId: 'p'),
    );
    await tester.tap(find.text('커플 연결 끊기'));
    await tester.pumpAndSettle();
    expect(find.textContaining('지난 기록에서 계속 볼 수 있어요'), findsOneWidget);
    await tester.tap(find.text('연결 끊기'));
    await tester.pumpAndSettle();
    expect(couples.archives, 1);
  });

  testWidgets('취소하면 아무것도 바뀌지 않는다', (tester) async {
    final couples = await pump(
      tester,
      couple: const Couple(id: 'c1', partnerId: 'p'),
    );
    await tester.tap(find.text('커플 연결 끊기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(couples.archives, 0);
  });

  testWidgets('커플이 없으면 연결 끊기 항목이 없다', (tester) async {
    await pump(tester, couple: null);
    expect(find.text('커플 연결 끊기'), findsNothing);
  });
}
