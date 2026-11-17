import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'package:woori_piece/features/trip/trip_discovery_banner.dart';

void main() {
  testWidgets('후보가 없으면 비교 승인 선택 경로를 안내한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripCandidatesProvider.overrideWith((ref) async => [])],
        child: const MaterialApp(home: Scaffold(body: TripDiscoveryBanner())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('기록 선택'), findsOneWidget);
  });
  testWidgets('비교 결과가 없을 때 새로 확인할 수 있다', (tester) async {
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripCandidatesProvider.overrideWith((ref) async {
            reads++;
            return [];
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: TripDiscoveryBanner())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('함께 간 기록 새로 확인'));
    await tester.pumpAndSettle();
    expect(reads, 2);
  });

  testWidgets('0개 안내를 닫으면 공간을 비우고 화면을 새로 열면 새로 확인할 수 있다', (tester) async {
    Widget screen() => ProviderScope(
      overrides: [tripCandidatesProvider.overrideWith((ref) async => [])],
      child: const MaterialApp(home: Scaffold(body: TripDiscoveryBanner())),
    );
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TripDiscoveryBanner)),
    );
    await tester.tap(find.byTooltip('안내 닫기'));
    await tester.pumpAndSettle();
    expect(find.text('기록 선택'), findsNothing);
    expect(find.byTooltip('함께 간 기록 새로 확인'), findsNothing);
    expect(tester.getSize(find.byType(TripDiscoveryBanner)), Size.zero);
    container.invalidate(tripCandidatesProvider);
    await tester.pumpAndSettle();
    expect(find.text('기록 선택'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('기록 선택'), findsOneWidget);
    expect(find.byTooltip('함께 간 기록 새로 확인'), findsOneWidget);
  });

  for (final permissionError in [false, true]) {
    testWidgets('0개 안내를 닫아도 ${permissionError ? '권한' : '새 후보'} 안내는 표시한다', (
      tester,
    ) async {
      var updated = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tripCandidatesProvider.overrideWith((ref) async {
              if (!updated) return [];
              if (permissionError) throw AppError.photoPermission;
              return [
                TripCandidate(
                  range: DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 1)),
                  regionIds: const ['32060'],
                  title: '속초시',
                ),
              ];
            }),
          ],
          child: const MaterialApp(home: Scaffold(body: TripDiscoveryBanner())),
        ),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(TripDiscoveryBanner)),
      );
      await tester.tap(find.byTooltip('안내 닫기'));
      await tester.pumpAndSettle();
      updated = true;
      container.invalidate(tripCandidatesProvider);
      await tester.pumpAndSettle();
      expect(
        find.text(permissionError ? '설정 열기' : '함께 간 여행 1개를 찾았어요'),
        findsOneWidget,
      );
    });
  }

  testWidgets('계정이 바뀌면 새 후보를 받기 전에 이전 계정의 후보를 보이지 않는다', (tester) async {
    final scope = NotifierProvider<_Scope, CandidateScope>(_Scope.new);
    final pending = Completer<List<TripCandidate>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          candidateScopeProvider.overrideWith((ref) => ref.watch(scope)),
          tripCandidatesProvider.overrideWith((ref) async {
            if (ref.watch(scope).userId == 'b') return pending.future;
            return [
              TripCandidate(
                range: DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 1)),
                regionIds: const ['32060'],
                title: '속초시',
              ),
            ];
          }),
        ],
        child: const MaterialApp(home: Scaffold(body: TripDiscoveryBanner())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('함께 간 여행 1개를 찾았어요'), findsOneWidget);
    ProviderScope.containerOf(
      tester.element(find.byType(TripDiscoveryBanner)),
    ).read(scope.notifier).set((userId: 'b', coupleId: 'c2'));
    await tester.pump();
    expect(find.text('함께 간 여행 1개를 찾았어요'), findsNothing);
    pending.complete([]);
  });
}

class _Scope extends Notifier<CandidateScope> {
  @override
  CandidateScope build() => (userId: 'a', coupleId: 'c1');
  void set(CandidateScope next) => state = next;
}
