import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/app/app.dart';
import 'package:woori_piece/app/router.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/features/map/view/province_map_page.dart';
import 'package:woori_piece/features/map/view/puzzle_map.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/map_data/map_asset.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';

import 'fakes.dart';

final provinces = MapAsset.parse(
  File('assets/map/provinces_v1.json').readAsStringSync(),
);
final regions = MapAsset.parse(
  File('assets/map/regions_v1.json').readAsStringSync(),
);

void main() {
  testWidgets('빈 조각을 탭하면 그 조각이 선택된 수동 여행을 만든다', (tester) async {
    final trips = FakeTripRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStageProvider.overrideWithValue(AppStage.ready),
          initialLocationProvider.overrideWithValue('/province/32'),
          provinceMapAssetProvider.overrideWith((ref) => provinces),
          regionMapAssetProvider.overrideWith((ref) => regions),
          currentCoupleProvider.overrideWith((ref) async => null),
          tripsProvider.overrideWith((ref) async => const []),
          homeRegionIdsProvider.overrideWith((ref) async => const {}),
          tripRepositoryProvider.overrideWithValue(trips),
        ],
        child: const WooriPieceApp(),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.renderObject<RenderBox>(find.byType(PuzzleMap));
    final layout = PuzzleLayout.build(
      asset: provinceAssetOf(regions, '32')!,
      size: box.size,
    );
    await tester.tapAt(box.localToGlobal(layout.labelPoints['32060']!));
    await tester.pumpAndSettle();

    expect(find.text('여행 만들기'), findsOneWidget);
    expect(find.widgetWithText(InputChip, '속초시'), findsOneWidget);
    await tester.tap(find.text('지도에 채우기'));
    await tester.pumpAndSettle();
    expect(trips.confirms.single.regionIds, ['32060']);
    expect(trips.confirms.single.source, TripSource.manual);
    expect(trips.confirms.single.title, '속초시');
  });
}
