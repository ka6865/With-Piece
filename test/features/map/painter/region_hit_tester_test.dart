import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/map_data/map_asset.dart';

import 'interior_point.dart';

void main() {
  final asset = MapAsset.parse(
    File('assets/map/regions_v1.json').readAsStringSync(),
  );
  final layout = PuzzleLayout.build(asset: asset, size: const Size(390, 600));
  final hitTester = layout.hitTester;

  test('229개 조각 모두 내부점 탭이 자기 조각을 고른다', () {
    expect(layout.polygons.map((p) => p.regionId).toSet().length, 229);
    final failures = <String>[];
    for (final feature in asset.features) {
      final candidates =
          layout.polygons.where((p) => p.regionId == feature.id).toList()
            ..sort((a, b) => b.area.compareTo(a.area));
      final point = interiorPointOf(candidates.first.rings);
      if (point == null || hitTester.hitTest(point) != feature.id) {
        failures.add('${feature.id} ${feature.name}');
      }
    }
    expect(failures, isEmpty);
  });

  test('구멍 내부는 바깥 조각으로 판정하지 않는다', () {
    final holed = layout.polygons.where((p) => p.rings.length > 1).toList();
    expect(holed.length, 6);
    for (final polygon in holed) {
      for (final hole in polygon.rings.skip(1)) {
        final point = interiorPointOf([hole]);
        expect(point, isNotNull);
        expect(hitTester.hitTest(point!), isNot(polygon.regionId));
      }
    }
  });

  test('울릉·독도 인셋의 내부점과 빈 모서리가 모두 울릉군이다', () {
    expect(layout.insetRects.keys, ['ulleung', 'dokdo']);
    for (final rect in layout.insetRects.values) {
      expect(rect.width, greaterThanOrEqualTo(44));
      expect(hitTester.hitTest(rect.topLeft + const Offset(1, 1)), '37430');
      expect(hitTester.hitTest(rect.bottomRight - const Offset(1, 1)), '37430');
    }
    for (final insetId in ['ulleung', 'dokdo']) {
      final polygon = layout.polygons.firstWhere((p) => p.insetId == insetId);
      expect(hitTester.hitTest(interiorPointOf(polygon.rings)!), '37430');
    }
  });

  test('본토 조각은 인셋 사각형에 걸치지 않는다', () {
    final mainland = layout.polygons.where((p) => p.insetId == null);
    for (final rect in layout.insetRects.values) {
      expect(
        mainland.where(
          (p) => p.bounds.overlaps(rect) && p.rings.first.any(rect.contains),
        ),
        isEmpty,
      );
    }
  });
}
