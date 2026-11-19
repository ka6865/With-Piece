import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/app/app.dart';
import 'package:woori_piece/app/router.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/features/map/painter/puzzle_painter.dart';
import 'package:woori_piece/features/map/view/puzzle_map.dart';
import 'package:woori_piece/map_data/map_asset.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';

import '../painter/interior_point.dart';

final provinces = MapAsset.parse(
  File('assets/map/provinces_v1.json').readAsStringSync(),
);
final regions = MapAsset.parse(
  File('assets/map/regions_v1.json').readAsStringSync(),
);

Widget appAt(String path) => ProviderScope(
  overrides: [
    provinceMapAssetProvider.overrideWith((ref) => provinces),
    regionMapAssetProvider.overrideWith((ref) => regions),
    appStageProvider.overrideWithValue(AppStage.ready),
    initialLocationProvider.overrideWithValue(path),
  ],
  child: const WooriPieceApp(),
);

// 화면의 PuzzleMap과 같은 크기로 레이아웃을 만들어 시도 내부점을 전역 좌표로 바꾼다
Future<void> tapProvinceByCode(WidgetTester tester, String code) async {
  final box = tester.renderObject<RenderBox>(find.byType(PuzzleMap));
  final layout = PuzzleLayout.build(asset: provinces, size: box.size);
  final polygon =
      layout.polygons
          .where((p) => p.regionId == code && p.insetId == null)
          .toList()
        ..sort((a, b) => b.area.compareTo(a.area));
  await tester.tapAt(box.localToGlobal(interiorPointOf(polygon.first.rings)!));
}

void main() {
  testWidgets('전국 화면은 17개 시도 진행률을 표시한다', (tester) async {
    await tester.pumpWidget(appAt('/map'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 25'), findsOneWidget);
    expect(find.text('0 / 1'), findsOneWidget);
  });

  testWidgets('시도 코드를 탭하면 해당 시도 화면으로 간다', (tester) async {
    await tester.pumpWidget(appAt('/map'));
    await tester.pumpAndSettle();
    await tapProvinceByCode(tester, '32');
    await tester.pumpAndSettle();
    expect(find.text('강원도'), findsOneWidget);
    expect(find.text('0 / 18 조각'), findsOneWidget);
  });

  testWidgets('시도 화면에서 뒤로 가면 전국 화면으로 돌아온다', (tester) async {
    await tester.pumpWidget(appAt('/map'));
    await tester.pumpAndSettle();
    await tapProvinceByCode(tester, '32');
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('우리들의 조각'), findsOneWidget);
    expect(find.text('0 / 25'), findsOneWidget);
  });

  testWidgets('경북 화면은 울릉·독도 인셋을 유지한다', (tester) async {
    await tester.pumpWidget(appAt('/province/37'));
    await tester.pumpAndSettle();
    expect(find.text('0 / 23 조각'), findsOneWidget);
    final map = tester.widget<PuzzleMap>(find.byType(PuzzleMap));
    expect(map.asset.insets.map((i) => i.regionId), ['37430', '37430']);
  });

  testWidgets('없는 시도 코드는 오류 화면을 표시한다', (tester) async {
    await tester.pumpWidget(appAt('/province/99'));
    await tester.pumpAndSettle();
    expect(find.text('지역을 찾을 수 없어요'), findsOneWidget);
  });

  testWidgets('조각 지도를 주면 채운 조각만 칠하고 시도는 경계만 긋는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PuzzleMap(
          asset: provinces,
          pieceAsset: regions,
          visitedRegionIds: const {'32060'},
          onRegionTap: (_) {},
        ),
      ),
    );
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((c) => c.painter)
        .whereType<PuzzlePainter>()
        .toList();
    final pieces = painters.singleWhere((p) => !p.bordersOnly);
    final borders = painters.singleWhere((p) => p.bordersOnly);
    // 강원 조각 하나만 칠하고 다른 강원 조각(고성군 32400)은 비워 둔다
    expect(pieces.layout.polygons.map((p) => p.regionId).toSet().length, 229);
    expect(pieces.visitedRegionIds, {'32060'});
    expect(pieces.visitedRegionIds.contains('32400'), isFalse);
    expect(borders.layout.polygons.map((p) => p.regionId).toSet().length, 17);
  });

  testWidgets('조각 지도 위에서도 시도를 누르면 시도 화면으로 간다', (tester) async {
    await tester.pumpWidget(appAt('/map'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PuzzleMap>(find.byType(PuzzleMap)).pieceAsset,
      regions,
    );
    await tapProvinceByCode(tester, '32');
    await tester.pumpAndSettle();
    expect(find.text('강원도'), findsOneWidget);
  });
}
