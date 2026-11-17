import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/map_data/geo_region_locator.dart';
import 'package:woori_piece/map_data/map_asset.dart';

void main() {
  final asset = MapAsset.parse(
    File('assets/map/regions_v1.json').readAsStringSync(),
  );
  final locator = GeoRegionLocator(asset);

  test('229개 조각의 경위도 내부점이 자기 코드로 판정된다', () {
    final wrong = <String>[];
    for (final feature in asset.features) {
      final polygon = feature.polygons.reduce(
        (a, b) => a.first.length >= b.first.length ? a : b,
      );
      final rings = [
        for (final ring in polygon)
          [for (final p in ring) Offset(p.lon, p.lat)],
      ];
      final point = labelPointOf(rings, precision: 0.0005);
      if (locator.regionAt(GeoPoint(point.dx, point.dy)) != feature.id) {
        wrong.add('${feature.id} ${feature.name}');
      }
    }
    expect(wrong, isEmpty);
  });

  test('실제 좌표를 코드로 판정한다', () {
    expect(
      locator.regionAt(const GeoPoint(128.5918, 38.2070)),
      '32060',
    ); // 속초시청
    expect(
      locator.regionAt(const GeoPoint(130.9057, 37.4844)),
      '37430',
    ); // 울릉군청
    expect(
      locator.regionAt(const GeoPoint(131.8695, 37.2395)),
      '37430',
    ); // 독도 동도
  });

  test('바다와 국외는 null이다', () {
    expect(locator.regionAt(const GeoPoint(130.0, 35.5)), isNull); // 동해
    expect(locator.regionAt(const GeoPoint(139.69, 35.68)), isNull); // 도쿄
  });
}
