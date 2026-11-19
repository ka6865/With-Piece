import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/features/map/view/puzzle_map.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/scan_store.dart';
import 'package:woori_piece/features/scan/solo_preview.dart';
import 'package:woori_piece/map_data/map_asset.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';

final provinces = MapAsset.parse(
  File('assets/map/provinces_v1.json').readAsStringSync(),
);
final regions = MapAsset.parse(
  File('assets/map/regions_v1.json').readAsStringSync(),
);

class _User extends Notifier<String> {
  @override
  String build() => 'a';
  void set(String userId) => state = userId;
}

final _user = NotifierProvider<_User, String>(_User.new);

// Supabase가 초기화되지 않은 환경이라 서버 provider에 닿으면 바로 실패한다
Future<void> pump(
  WidgetTester tester,
  Future<ScanSnapshot> Function() scan,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('me'),
        provinceMapAssetProvider.overrideWith((ref) => provinces),
        regionMapAssetProvider.overrideWith((ref) => regions),
        scanSnapshotProvider.overrideWith((ref, userId) => scan()),
      ],
      child: const MaterialApp(home: Scaffold(body: SoloPreview())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('계정 전환 중에는 이전 계정의 스캔 결과를 표시하지 않는다', (tester) async {
    final pending = Completer<ScanSnapshot>();
    final container = ProviderContainer(
      overrides: [
        sessionUserIdProvider.overrideWith((ref) => ref.watch(_user)),
        provinceMapAssetProvider.overrideWith((ref) => provinces),
        regionMapAssetProvider.overrideWith((ref) => regions),
        scanSnapshotProvider.overrideWith((ref, userId) {
          if (userId == 'a') {
            return Future.value(
              ScanSnapshot({
                PhotoDay(DateTime(2026, 10, 3), '32060'): 2,
              }, DateTime(2026, 11, 1)),
            );
          }
          return pending.future;
        }),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SoloPreview())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('1조각'), findsOneWidget);

    container.read(_user.notifier).set('b');
    await tester.pump();

    expect(find.textContaining('1조각'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('내 스캔 결과로 칠한 지도를 흐리게 보인다', (tester) async {
    await pump(
      tester,
      () async => ScanSnapshot({
        PhotoDay(DateTime(2026, 10, 3), '32060'): 2,
        PhotoDay(DateTime(2026, 10, 4), '37020'): 1,
      }, DateTime(2026, 11, 1)),
    );
    expect(find.byType(ImageFiltered), findsOneWidget);
    final map = tester.widget<PuzzleMap>(find.byType(PuzzleMap));
    expect(map.visitedRegionIds, {'32', '37'});
    expect(find.textContaining('2조각'), findsOneWidget);
    expect(find.textContaining('연인이 들어오면'), findsOneWidget);
  });

  testWidgets('사진 권한이 없으면 지도 대신 권한 안내를 보인다', (tester) async {
    await pump(tester, () async => throw AppError.photoPermission);
    expect(find.byType(PuzzleMap), findsNothing);
    expect(find.text('설정 열기'), findsOneWidget);
  });
}
