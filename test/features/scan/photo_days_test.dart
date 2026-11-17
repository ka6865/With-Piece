import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/map_data/geo_region_locator.dart';
import 'package:woori_piece/map_data/map_asset.dart';

void main() {
  final locator = GeoRegionLocator(
    MapAsset.parse(File('assets/map/regions_v1.json').readAsStringSync()),
  );

  test('같은 날 같은 조각은 사진 수로 접고 조각 밖 사진은 버린다', () {
    final days = aggregatePhotoDays([
      PhotoMeta(DateTime(2026, 10, 3, 9), const GeoPoint(128.58, 38.19)), // 속초
      PhotoMeta(
        DateTime(2026, 10, 3, 18),
        const GeoPoint(128.581, 38.191),
      ), // 속초
      PhotoMeta(
        DateTime(2026, 10, 4, 10),
        const GeoPoint(128.47, 38.38),
      ), // 고성(강원)
      PhotoMeta(DateTime(2026, 10, 4, 11), const GeoPoint(130.0, 35.5)), // 바다
    ], locator);
    expect(days, {
      PhotoDay(DateTime(2026, 10, 3), '32060'): 2,
      PhotoDay(DateTime(2026, 10, 4), '32400'): 1,
    });
  });

  test('날짜는 촬영 시각의 현지 날짜다', () {
    final days = aggregatePhotoDays([
      PhotoMeta(DateTime(2026, 10, 3, 23, 59), const GeoPoint(128.58, 38.19)),
      PhotoMeta(DateTime(2026, 10, 4, 0, 1), const GeoPoint(128.58, 38.19)),
    ], locator);
    expect(days.keys.map((d) => d.day), [
      DateTime(2026, 10, 3),
      DateTime(2026, 10, 4),
    ]);
  });
}
