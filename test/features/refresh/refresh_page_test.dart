import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/refresh/refresh_page.dart';
import 'package:woori_piece/features/refresh/refresh_providers.dart';
import 'package:woori_piece/features/scan/home_regions.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/scan_store.dart';

import '../auth/fakes.dart';
import '../trip/fakes.dart';

void main() {
  testWidgets('추천한 사는 곳을 정하면 저장하고 생활권으로 지정한다', (tester) async {
    final couples = FakeCoupleRepository();
    final trips = FakeTripRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          currentCoupleProvider.overrideWith(
            (ref) async => const Couple(id: 'c1', partnerId: 'p'),
          ),
          refreshStatesProvider.overrideWith((ref) async => const {}),
          coupleRepositoryProvider.overrideWithValue(couples),
          tripRepositoryProvider.overrideWithValue(trips),
          regionNamesProvider.overrideWith(
            (ref) async => {'osan': '오산시', 'jeju': '제주시'},
          ),
          scanSnapshotProvider.overrideWith(
            (ref) async => ScanSnapshot({
              PhotoDay(DateTime(2025, 1, 1), 'osan'): 1,
              PhotoDay(DateTime(2025, 1, 2), 'osan'): 1,
              PhotoDay(DateTime(2025, 5, 1), 'jeju'): 300,
            }, DateTime(2026, 11, 1)),
          ),
        ],
        child: const MaterialApp(home: RefreshPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('오산시에서 사진을 가장 많이 찍었어요. 사는 곳으로 정할까요?'), findsOneWidget);
    await tester.tap(find.text('정하기'));
    await tester.pumpAndSettle();
    expect(couples.homeRegions, ['osan']);
    expect(trips.overrideCalls, [('osan', OverrideKind.home)]);
  });
}
