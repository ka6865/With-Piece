import 'dart:ui';

import '../features/map/painter/puzzle_layout.dart';
import '../features/map/painter/region_hit_tester.dart';
import 'map_asset.dart';

// 사진 위치를 조각 코드로 바꾼다. 탭과 같은 판정 로직을 경위도에 그대로 쓴다(설계 5.1).
// 인셋이 없으므로 울릉군도 실제 좌표에서 판정된다
class GeoRegionLocator {
  GeoRegionLocator(MapAsset asset)
    : _hitTester = RegionHitTester(
        [
          for (final feature in asset.features)
            for (final polygon in feature.polygons)
              ScaledPolygon(
                regionId: feature.id,
                rings: [
                  for (final ring in polygon)
                    [for (final p in ring) Offset(p.lon, p.lat)],
                ],
              ),
        ],
        insetRects: const {},
        insetRegionIds: const {},
      );

  final RegionHitTester _hitTester;

  // 바다나 국외면 null
  String? regionAt(GeoPoint point) =>
      _hitTester.hitTest(Offset(point.lon, point.lat));
}
