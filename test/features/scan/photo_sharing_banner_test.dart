import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
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
}
