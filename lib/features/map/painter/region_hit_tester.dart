import 'dart:ui';

import 'puzzle_layout.dart';

// 그리기와 같은 화면 좌표 캐시(PuzzleLayout.polygons)로 탭을 판정한다
class RegionHitTester {
  const RegionHitTester(
    this.polygons, {
    required this.insetRects,
    required this.insetRegionIds,
  });

  final List<ScaledPolygon> polygons;
  final Map<String, Rect> insetRects;
  final Map<String, String> insetRegionIds;

  String? hitTest(Offset point) {
    // 인셋 영역 안의 탭은 그 인셋만, 밖의 탭은 본토만 후보로 삼는다.
    // 섞으면 인셋의 작은 폴리곤이 최소 면적 규칙에서 항상 이긴다
    String? activeInset;
    for (final entry in insetRects.entries) {
      if (entry.value.contains(point)) {
        activeInset = entry.key;
        break;
      }
    }
    String? bestId;
    var bestArea = double.infinity;
    for (final polygon in polygons) {
      if (polygon.insetId != activeInset) continue;
      if (!polygon.bounds.contains(point)) continue;
      if (!isInside(point, polygon.rings.first)) continue;
      if (polygon.rings.skip(1).any((hole) => isInside(point, hole))) continue;
      // 해안에서 큰 지역의 외곽이 작은 섬을 감싸는 경우 작은 쪽을 고른다
      if (polygon.area < bestArea) {
        bestArea = polygon.area;
        bestId = polygon.regionId;
      }
    }
    // 독도처럼 실제 육지가 작은 인셋도 사각형 전체를 탭 영역으로 쓴다
    return bestId ?? (activeInset == null ? null : insetRegionIds[activeInset]);
  }
}

// 짝수-홀수 교차 판정
bool isInside(Offset point, List<Offset> ring) {
  var inside = false;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    if ((a.dy > point.dy) != (b.dy > point.dy)) {
      final x = (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx;
      if (point.dx < x) inside = !inside;
    }
  }
  return inside;
}
