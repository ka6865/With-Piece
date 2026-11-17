import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/auth/started_on_page.dart';

import 'fakes.dart';

class DateContext extends Notifier<({String userId, Couple couple})> {
  @override
  ({String userId, Couple couple}) build() => (
    userId: 'me',
    couple: Couple(id: 'c1', partnerId: 'p', startedOn: DateTime(2020, 1, 1)),
  );

  void change({String? userId, String? coupleId, DateTime? date}) => state = (
    userId: userId ?? state.userId,
    couple: Couple(
      id: coupleId ?? state.couple.id,
      partnerId: 'p',
      startedOn: date ?? state.couple.startedOn,
    ),
  );
}

final dateContextProvider =
    NotifierProvider<DateContext, ({String userId, Couple couple})>(
      DateContext.new,
    );

class SavingCoupleRepository extends FakeCoupleRepository {
  Future<Result<void>>? pendingSave;

  @override
  Future<Result<void>> setStartedOn(DateTime date) {
    startedOnCalls.add(date);
    return pendingSave ?? Future.value(const Ok(null));
  }
}

Future<SavingCoupleRepository> pumpPage(
  WidgetTester tester, {
  bool isEditing = true,
  bool withBackStack = false,
  SavingCoupleRepository? repository,
  Future<Couple> Function(Ref)? loadCouple,
}) async {
  final couples = repository ?? SavingCoupleRepository();
  const page = StartedOnPage(isEditing: true);
  Widget app = MaterialApp(home: StartedOnPage(isEditing: isEditing));
  if (withBackStack) {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => context.push('/edit'),
              child: const Text('설정에서 수정'),
            ),
          ),
        ),
        GoRoute(path: '/edit', builder: (_, _) => page),
      ],
    );
    addTearDown(router.dispose);
    app = MaterialApp.router(routerConfig: router);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        coupleRepositoryProvider.overrideWithValue(couples),
        sessionUserIdProvider.overrideWith(
          (ref) => ref.watch(dateContextProvider).userId,
        ),
        currentCoupleProvider.overrideWith(
          loadCouple ?? (ref) async => ref.watch(dateContextProvider).couple,
        ),
      ],
      child: app,
    ),
  );
  await tester.pumpAndSettle();
  if (withBackStack) {
    await tester.tap(find.text('설정에서 수정'));
    await tester.pumpAndSettle();
  }
  return couples;
}

Future<void> chooseDate(WidgetTester tester, String date) async {
  await tester.tap(find.text('날짜 바꾸기'));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Switch to input'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), date);
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('날짜 선택을 취소하면 저장하지 않고 수정 화면에 남는다', (tester) async {
    final couples = await pumpPage(tester);
    await tester.tap(find.text('날짜 바꾸기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(couples.startedOnCalls, isEmpty);
    expect(find.text('날짜 바꾸기'), findsOneWidget);
  });

  testWidgets('날짜를 늦추면 삭제될 승인과 스캔 기록을 알리고 취소 시 저장하지 않는다', (tester) async {
    final couples = await pumpPage(tester);
    await chooseDate(tester, '01/02/2020');
    expect(
      find.textContaining('동기화하면 두 사람의 새 날짜 이전 스캔 기록과 비교 승인이 삭제'),
      findsOneWidget,
    );
    expect(find.textContaining('삭제된 비교 승인은'), findsOneWidget);
    expect(couples.startedOnCalls, isEmpty);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(couples.startedOnCalls, isEmpty);
    expect(find.text('날짜 바꾸기'), findsOneWidget);
  });

  testWidgets('늦춘 날짜를 확인하고 저장하면 GoRouter로 설정 화면에 돌아간다', (tester) async {
    final couples = await pumpPage(tester, withBackStack: true);
    await chooseDate(tester, '01/02/2020');
    expect(couples.startedOnCalls, isEmpty);
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();
    expect(couples.startedOnCalls, [DateTime(2020, 1, 2)]);
    expect(find.text('설정에서 수정'), findsOneWidget);
    expect(find.text('날짜 바꾸기'), findsNothing);
  });

  for (final date in ['01/01/2020', '12/31/2019']) {
    testWidgets('같거나 이른 날짜 $date 저장은 삭제 확인 없이 완료를 알린다', (tester) async {
      final couples = await pumpPage(tester);
      await chooseDate(tester, date);
      expect(couples.startedOnCalls, hasLength(1));
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('사귄 날을 저장했어요'), findsOneWidget);
    });
  }

  testWidgets('온보딩의 최초 날짜 저장은 삭제 확인이나 수정 화면 이동 없이 유지한다', (tester) async {
    final couples = await pumpPage(tester, isEditing: false);
    await tester.tap(find.text('날짜 고르기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(couples.startedOnCalls, hasLength(1));
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('언제부터 함께였나요?'), findsOneWidget);
  });

  testWidgets('저장 실패는 수정 화면에 남아서 알린다', (tester) async {
    final repository = SavingCoupleRepository()
      ..pendingSave = Future.value(const Err(AppError.network));
    await pumpPage(tester, repository: repository, withBackStack: true);
    await chooseDate(tester, '01/01/2020');
    expect(find.text('저장하지 못했어요'), findsOneWidget);
    expect(find.text('날짜 바꾸기'), findsOneWidget);
  });

  testWidgets('저장 도중 화면을 떠나도 폐기된 context나 ref를 쓰지 않는다', (tester) async {
    final completion = Completer<Result<void>>();
    final repository = SavingCoupleRepository()
      ..pendingSave = completion.future;
    await pumpPage(tester, repository: repository);
    await chooseDate(tester, '01/01/2020');
    expect(repository.startedOnCalls, hasLength(1));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    completion.complete(const Ok(null));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final accountChange in [true, false]) {
    testWidgets('날짜 선택 중 ${accountChange ? '계정' : '커플'}이 바뀌면 이전 선택을 저장하지 않는다', (
      tester,
    ) async {
      final couples = await pumpPage(tester);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(StartedOnPage)),
      );
      await tester.tap(find.text('날짜 바꾸기'));
      await tester.pumpAndSettle();
      scope
          .read(dateContextProvider.notifier)
          .change(
            userId: accountChange ? 'new-user' : null,
            coupleId: accountChange ? null : 'new-couple',
          );
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(couples.startedOnCalls, isEmpty);
    });
  }

  testWidgets('선택 중 상대가 날짜를 앞당기면 최신 날짜 기준으로 삭제를 확인한다', (tester) async {
    final couples = await pumpPage(tester);
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(StartedOnPage)),
    );
    await tester.tap(find.text('날짜 바꾸기'));
    await tester.pumpAndSettle();
    scope
        .read(dateContextProvider.notifier)
        .change(date: DateTime(2019, 12, 31));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('사귄 날을 늦출까요?'), findsOneWidget);
    expect(couples.startedOnCalls, isEmpty);
  });

  testWidgets('삭제 확인 중 기준 날짜가 바뀌면 이전 확인으로 덮어쓰지 않는다', (tester) async {
    final couples = await pumpPage(tester);
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(StartedOnPage)),
    );
    await chooseDate(tester, '01/02/2020');
    scope
        .read(dateContextProvider.notifier)
        .change(date: DateTime(2019, 12, 31));
    await tester.pumpAndSettle();
    await tester.tap(find.text('변경하기'));
    await tester.pumpAndSettle();
    expect(couples.startedOnCalls, isEmpty);
  });

  testWidgets('저장 중 계정이 바뀌면 새 화면에 성공 안내를 띄우지 않는다', (tester) async {
    final completion = Completer<Result<void>>();
    final repository = SavingCoupleRepository()
      ..pendingSave = completion.future;
    await pumpPage(tester, repository: repository);
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(StartedOnPage)),
    );
    await chooseDate(tester, '01/01/2020');
    scope.read(dateContextProvider.notifier).change(userId: 'new-user');
    await tester.pumpAndSettle();
    completion.complete(const Ok(null));
    await tester.pumpAndSettle();
    expect(find.text('사귄 날을 저장했어요'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('자기 저장에 따른 커플 갱신 중에도 성공하면 이전 화면에 돌아간다', (tester) async {
    final completion = Completer<Result<void>>();
    final reloaded = Completer<void>();
    var refreshing = false;
    final repository = SavingCoupleRepository()
      ..pendingSave = completion.future;
    await pumpPage(
      tester,
      repository: repository,
      withBackStack: true,
      loadCouple: (ref) async {
        final couple = ref.watch(dateContextProvider).couple;
        if (refreshing) await reloaded.future;
        return couple;
      },
    );
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(StartedOnPage)),
    );
    await chooseDate(tester, '01/01/2020');
    refreshing = true;
    scope.invalidate(currentCoupleProvider);
    await tester.pump();
    expect(scope.read(currentCoupleProvider).isLoading, isTrue);
    completion.complete(const Ok(null));
    await tester.pumpAndSettle();
    expect(find.text('설정에서 수정'), findsOneWidget);
    expect(find.text('날짜 바꾸기'), findsNothing);
    reloaded.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('커플을 다시 읽는 중에 고른 날짜도 재조회가 끝나면 저장한다', (tester) async {
    Completer<Couple>? reload;
    final couples = await pumpPage(
      tester,
      loadCouple: (ref) {
        final couple = ref.watch(dateContextProvider).couple;
        return reload?.future ?? Future.value(couple);
      },
    );
    reload = Completer<Couple>();
    ProviderScope.containerOf(
      tester.element(find.byType(StartedOnPage)),
    ).invalidate(currentCoupleProvider);
    await chooseDate(tester, '01/01/2019');
    expect(couples.startedOnCalls, isEmpty);
    reload.complete(
      Couple(id: 'c1', partnerId: 'p', startedOn: DateTime(2020, 1, 1)),
    );
    await tester.pumpAndSettle();
    expect(couples.startedOnCalls, [DateTime(2019, 1, 1)]);
  });

  testWidgets('저장 전 커플 재조회가 실패하면 저장하지 않고 실패를 알린다', (tester) async {
    Completer<Couple>? reload;
    final couples = await pumpPage(
      tester,
      loadCouple: (ref) {
        final couple = ref.watch(dateContextProvider).couple;
        return reload?.future ?? Future.value(couple);
      },
    );
    reload = Completer<Couple>();
    ProviderScope.containerOf(
      tester.element(find.byType(StartedOnPage)),
    ).invalidate(currentCoupleProvider);
    await chooseDate(tester, '01/01/2019');
    reload.completeError(AppError.network);
    await tester.pumpAndSettle();
    expect(couples.startedOnCalls, isEmpty);
    expect(find.text('저장하지 못했어요'), findsOneWidget);
  });
}
