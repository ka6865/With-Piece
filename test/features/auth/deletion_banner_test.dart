import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/account_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/auth/account_state.dart';

class FakeAccountRepository implements AccountRepository {
  int cancels = 0;

  @override
  Future<Result<void>> cancelDeletion() async {
    cancels++;
    return const Ok(null);
  }

  @override
  Future<Result<DateTime?>> myDeletionDate() async => const Ok(null);

  @override
  Future<Result<List<DateTime>>> partnerDeletionDates() async => const Ok([]);

  @override
  Future<Result<void>> requestDeletion() async => const Ok(null);
}

Future<FakeAccountRepository> pump(
  WidgetTester tester, {
  DateTime? mine,
  List<DateTime> partner = const [],
}) async {
  final repo = FakeAccountRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(repo),
        myDeletionDateProvider.overrideWith((ref) async => mine),
        partnerDeletionDatesProvider.overrideWith((ref) async => partner),
      ],
      child: const MaterialApp(home: Scaffold(body: DeletionBanners())),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('상대가 삭제를 요청했으면 기록이 사라지는 날을 알린다', (tester) async {
    await pump(tester, partner: [DateTime(2026, 12, 17)]);
    expect(find.text('상대가 계정 삭제를 요청해 12월 17일에 함께한 기록이 사라져요'), findsOneWidget);
  });

  testWidgets('내가 삭제를 요청한 상태면 취소할 수 있다', (tester) async {
    final repo = await pump(tester, mine: DateTime(2026, 12, 17));
    expect(find.textContaining('12월 17일에 계정이 삭제돼요'), findsOneWidget);
    await tester.tap(find.text('삭제 취소'));
    await tester.pumpAndSettle();
    expect(repo.cancels, 1);
  });

  testWidgets('요청이 없으면 아무것도 보이지 않는다', (tester) async {
    await pump(tester);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(Text), findsNothing);
  });
}
