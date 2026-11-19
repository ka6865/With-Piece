import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/features/map/painter/puzzle_painter.dart';
import 'package:woori_piece/features/map/view/puzzle_map.dart';
import 'package:woori_piece/map_data/map_asset.dart';

import 'interior_point.dart';

void main() {
  test('구멍이 있는 폴리곤 경로는 evenOdd를 쓴다', () {
    final polygonWithHole = ScaledPolygon(
      regionId: 'test',
      rings: const [
        [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 10),
          Offset(0, 10),
          Offset(0, 0),
        ],
        [Offset(4, 4), Offset(6, 4), Offset(6, 6), Offset(4, 6), Offset(4, 4)],
      ],
    );
    final path = PuzzlePainter.buildPath(polygonWithHole);
    expect(path.fillType, PathFillType.evenOdd);
    expect(path.contains(const Offset(5, 5)), isFalse);
    expect(path.contains(const Offset(1, 1)), isTrue);
  });

  testWidgets('탭 결과를 코드로 전달한다', (tester) async {
    final asset = MapAsset.parse(
      File('assets/map/regions_v1.json').readAsStringSync(),
    );
    final layout = PuzzleLayout.build(asset: asset, size: const Size(390, 600));
    final sokcho = layout.polygons.firstWhere((p) => p.regionId == '32060');
    final knownSokchoPoint = interiorPointOf(sokcho.rings)!;

    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 390,
            height: 600,
            child: PuzzleMap(
              asset: asset,
              visitedRegionIds: const {},
              onRegionTap: (id) => tapped = id,
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(knownSokchoPoint);
    expect(tapped, '32060');
  });

  testWidgets('VoiceOver 지역 동작은 실제 지역 코드를 전달한다', (tester) async {
    final semantics = tester.ensureSemantics();
    final asset = MapAsset.parse(
      File('assets/map/regions_v1.json').readAsStringSync(),
    );
    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 390,
          height: 600,
          child: PuzzleMap(
            asset: asset,
            visitedRegionIds: const {},
            onRegionTap: (id) => tapped = id,
          ),
        ),
      ),
    );

    final semanticsOwner =
        tester.binding.renderViews.single.owner!.semanticsOwner!;
    final root = semanticsOwner.rootSemanticsNode!;
    final nodes = <SemanticsNode>[];
    bool collect(SemanticsNode node) {
      nodes.add(node);
      node.visitChildren(collect);
      return true;
    }

    collect(root);
    final region = nodes.singleWhere(
      (node) => node.getSemanticsData().label == '속초시, 미방문',
    );
    expect(region.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    semanticsOwner.performAction(region.id, SemanticsAction.tap);
    await tester.pump();

    expect(tapped, '32060');
    semantics.dispose();
  });

  testWidgets('확대한 상태에서도 탭이 같은 조각을 고른다', (tester) async {
    final asset = MapAsset.parse(
      File('assets/map/regions_v1.json').readAsStringSync(),
    );
    final layout = PuzzleLayout.build(asset: asset, size: const Size(390, 600));
    final sokcho = layout.polygons.firstWhere((p) => p.regionId == '32060');
    final point = interiorPointOf(sokcho.rings)!;

    String? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 390,
            height: 600,
            child: PuzzleMap(
              asset: asset,
              visitedRegionIds: const {},
              onRegionTap: (id) => tapped = id,
            ),
          ),
        ),
      ),
    );
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    expect(viewer.maxScale, 8);
    // 속초가 화면 중앙 근처에 오도록 3배 확대한다
    final matrix = Matrix4.identity()
      ..translateByDouble(195 - point.dx * 3, 300 - point.dy * 3, 0, 1)
      ..scaleByDouble(3, 3, 1, 1);
    viewer.transformationController!.value = matrix;
    await tester.pump();
    await tester.tapAt(MatrixUtils.transformPoint(matrix, point));
    expect(tapped, '32060');
  });

  testWidgets('확대 배율을 지역명 레이어에 전달해 글씨 크기를 유지한다', (tester) async {
    final asset = MapAsset.parse(
      File('assets/map/regions_v1.json').readAsStringSync(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PuzzleMap(
          asset: asset,
          visitedRegionIds: const {},
          onRegionTap: (_) {},
        ),
      ),
    );
    MapLabelPainter labels() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<MapLabelPainter>()
        .single;
    expect(labels().zoom, 1);
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    viewer.transformationController!.value = Matrix4.diagonal3Values(4, 4, 1);
    await tester.pump();
    expect(labels().zoom, 4);
    expect(labels().fontSize, MapLabelPainter.screenFontSize / 4);
  });
}
