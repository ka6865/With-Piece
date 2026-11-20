import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/account_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/auth/account_state.dart';
import 'package:woori_piece/features/scan/scan_store.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/photo_days.dart';

class FakeAccountRepository implements AccountRepository {
  int cancels = 0;
  Result<void> cancelResult = const Ok(null);
  Future<Result<DateTime?>> Function()? readDeletionDate;

  @override
  Future<Result<void>> cancelDeletion() async {
    cancels++;
    return cancelResult;
  }

  @override
  Future<Result<DateTime?>> myDeletionDate() async =>
      await readDeletionDate?.call() ?? const Ok(null);

  @override
  Future<Result<List<DateTime>>> partnerDeletionDates() async => const Ok([]);

  @override
  Future<Result<void>> requestDeletion() async => const Ok(null);
}

Future<FakeAccountRepository> pump(
  WidgetTester tester, {
  DateTime? mine,
  List<DateTime?> mineSequence = const [],
  List<DateTime> partner = const [],
}) async {
  final repo = FakeAccountRepository();
  var mineReads = 0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        accountRepositoryProvider.overrideWithValue(repo),
        sessionUserIdProvider.overrideWithValue('me'),
        myDeletionDateProvider('me').overrideWith((ref) async {
          if (mineSequence.isEmpty) return mine;
          final index = mineReads++;
          return mineSequence[index < mineSequence.length
              ? index
              : mineSequence.length - 1];
        }),
        partnerDeletionDatesProvider('me').overrideWith((ref) async => partner),
      ],
      child: const MaterialApp(home: Scaffold(body: DeletionBanners())),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  test('다른 기기에서 삭제를 요청하면 기존 스캔 파일을 삭제한다', () async {
    const userId = 'remote-delete';
    final folder = await Directory.systemTemp.createTemp('remote-delete');
    addTearDown(() => folder.delete(recursive: true));
    addTearDown(() => ScanStore.allowUserAfterDeletionCanceled(userId));
    final store = ScanStore(folder, userId: userId);
    await store.write(
      ScanSnapshot({
        PhotoDay(DateTime(2026, 10, 3), '32060'): 1,
      }, DateTime(2026, 11, 20)),
    );
    final repo = FakeAccountRepository()
      ..readDeletionDate = () async => Ok(DateTime(2026, 12, 20));
    final container = ProviderContainer.test(
      overrides: [
        sessionUserIdProvider.overrideWithValue(userId),
        accountRepositoryProvider.overrideWithValue(repo),
        scanStoreProvider(userId).overrideWith((ref) => store),
      ],
    );
    await container.read(myDeletionDateProvider(userId).future);
    expect(store.isDeletionPending, isTrue);
    expect(await store.read(), ScanSnapshot.empty);
  });

  test('다른 기기의 삭제 취소를 조회하면 스캔 차단을 해제한다', () async {
    const userId = 'remote-cancel';
    final folder = await Directory.systemTemp.createTemp('remote-cancel');
    addTearDown(() => folder.delete(recursive: true));
    final store = ScanStore(folder, userId: userId);
    addTearDown(() => ScanStore.allowUserAfterDeletionCanceled(store.userId));
    DateTime? deletionDate = DateTime(2026, 12, 17);
    final repo = FakeAccountRepository()
      ..readDeletionDate = () async => Ok(deletionDate);
    final container = ProviderContainer.test(
      overrides: [
        sessionUserIdProvider.overrideWithValue(userId),
        accountRepositoryProvider.overrideWithValue(repo),
        scanStoreProvider(userId).overrideWith((ref) => store),
      ],
    );

    final provider = myDeletionDateProvider(userId);
    await container.read(provider.future);
    expect(store.isDeletionPending, isTrue);

    deletionDate = null;
    container.invalidate(provider);
    await container.read(provider.future);
    expect(store.isDeletionPending, isFalse);
  });

  test('삭제 요청 전에 시작한 조회는 새 스캔 차단을 풀지 못한다', () async {
    const userId = 'stale-deletion-query';
    final store = ScanStore(Directory.systemTemp, userId: userId);
    addTearDown(() => ScanStore.allowUserAfterDeletionCanceled(store.userId));
    final response = Completer<Result<DateTime?>>();
    final repo = FakeAccountRepository()
      ..readDeletionDate = () => response.future;
    final container = ProviderContainer.test(
      overrides: [
        sessionUserIdProvider.overrideWithValue(userId),
        accountRepositoryProvider.overrideWithValue(repo),
      ],
    );

    final pending = container.read(myDeletionDateProvider(userId).future);
    ScanStore.blockUser(store.userId);
    response.complete(const Ok(null));
    await pending;
    expect(store.isDeletionPending, isTrue);
  });

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

  testWidgets('삭제 취소가 성공하면 배너를 새 상태로 갱신한다', (tester) async {
    final repo = await pump(
      tester,
      mineSequence: [DateTime(2026, 12, 17), null],
    );

    await tester.tap(find.text('삭제 취소'));
    await tester.pumpAndSettle();

    expect(repo.cancels, 1);
    expect(find.textContaining('계정이 삭제돼요'), findsNothing);
  });

  testWidgets('삭제 취소 요청 상태가 바뀌면 일정을 다시 조회하고 안내한다', (tester) async {
    final repo = await pump(
      tester,
      mineSequence: [DateTime(2026, 12, 17), null],
    );
    repo.cancelResult = const Err(AppError.validation);
    await tester.tap(find.text('삭제 취소'));
    await tester.pumpAndSettle();
    expect(
      find.text('삭제 요청 상태가 바뀌었거나 취소 가능 기간이 끝났어요. 삭제 일정을 다시 확인해 주세요.'),
      findsOneWidget,
    );
    expect(find.textContaining('계정이 삭제돼요'), findsNothing);
  });

  testWidgets('요청이 없으면 아무것도 보이지 않는다', (tester) async {
    await pump(tester);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(Text), findsNothing);
  });
}
