import 'dart:math' as math;
import 'dart:ui';

import '../../../map_data/map_asset.dart';
import 'map_projection.dart';
import 'region_hit_tester.dart';

class ScaledPolygon {
  ScaledPolygon({required this.regionId, required this.rings, this.insetId})
    : bounds = boundsOf(rings.first),
      area = areaOf(rings.first);

  final String regionId;
  final List<List<Offset>> rings;
  final String? insetId;
  final Rect bounds;
  final double area;
}

// 캔버스 크기에 맞춘 화면 좌표 폴리곤 캐시. 그리기와 탭 판정이 이 값 하나를 함께 쓴다
class PuzzleLayout {
  const PuzzleLayout({
    required this.size,
    required this.polygons,
    required this.insetRects,
    required this.insetRegionIds,
    required this.labelPoints,
  });

  static const insetSideRatio = 0.18;
  static const insetMargin = 8.0;
  static const minTapSide = 44.0;

  factory PuzzleLayout.build({required MapAsset asset, required Size size}) {
    final mainland = MapProjection.fit(bbox: asset.mainlandBbox, size: size);
    // 본토에서는 인셋에 속한 폴리곤만 뺀다. 지역 단위로 빼면 시도 애셋에서
    // 경북 본토까지 사라진다
    final insetPolygons = <(String, int)>{
      for (final inset in asset.insets)
        for (final index in inset.polygonIndexes) (inset.regionId, index),
    };
    final polygons = <ScaledPolygon>[
      for (final feature in asset.features)
        for (var i = 0; i < feature.polygons.length; i++)
          if (!insetPolygons.contains((feature.id, i)))
            ScaledPolygon(
              regionId: feature.id,
              rings: [
                for (final ring in feature.polygons[i])
                  ring.map(mainland.project).toList(),
              ],
            ),
    ];

    // 독도처럼 작은 인셋도 최소 탭 영역 44x44를 보장한다
    final insetSide = math.max(
      minTapSide,
      math.min(size.width, size.height) * insetSideRatio,
    );
    final insetRects = <String, Rect>{};
    for (var index = 0; index < asset.insets.length; index++) {
      final inset = asset.insets[index];
      // 목록 마지막 인셋이 가장 아래에 온다
      final fromBottom = asset.insets.length - 1 - index;
      final rect = Rect.fromLTWH(
        size.width - insetMargin - insetSide,
        size.height -
            insetMargin -
            insetSide * (fromBottom + 1) -
            insetMargin * fromBottom,
        insetSide,
        insetSide,
      );
      insetRects[inset.id] = rect;
      final projection = MapProjection.fit(bbox: inset.bbox, size: rect.size);
      final feature = asset.byId(inset.regionId)!;
      for (final polygonIndex in inset.polygonIndexes) {
        polygons.add(
          ScaledPolygon(
            regionId: inset.regionId,
            insetId: inset.id,
            rings: [
              for (final ring in feature.polygons[polygonIndex])
                ring.map((p) => projection.project(p) + rect.topLeft).toList(),
            ],
          ),
        );
      }
    }

    return PuzzleLayout(
      size: size,
      polygons: polygons,
      insetRects: insetRects,
      insetRegionIds: {
        for (final inset in asset.insets) inset.id: inset.regionId,
      },
      labelPoints: _labelPointsOf(polygons),
    );
  }

  final Size size;
  final List<ScaledPolygon> polygons;
  final Map<String, Rect> insetRects;
  final Map<String, String> insetRegionIds;
  final Map<String, Offset> labelPoints;

  // 조각마다 화면 면적이 가장 큰 폴리곤에 이름을 둔다
  static Map<String, Offset> _labelPointsOf(List<ScaledPolygon> polygons) {
    final largest = <String, ScaledPolygon>{};
    for (final polygon in polygons) {
      final current = largest[polygon.regionId];
      if (current == null || polygon.area > current.area) {
        largest[polygon.regionId] = polygon;
      }
    }
    return {
      for (final MapEntry(key: id, value: polygon) in largest.entries)
        id: labelPointOf(polygon.rings),
    };
  }

  RegionHitTester get hitTester => RegionHitTester(
    polygons,
    insetRects: insetRects,
    insetRegionIds: insetRegionIds,
  );
}

Rect boundsOf(List<Offset> ring) {
  var left = double.infinity, top = double.infinity;
  var right = double.negativeInfinity, bottom = double.negativeInfinity;
  for (final p in ring) {
    left = math.min(left, p.dx);
    top = math.min(top, p.dy);
    right = math.max(right, p.dx);
    bottom = math.max(bottom, p.dy);
  }
  return Rect.fromLTRB(left, top, right, bottom);
}

// 신발끈 공식
double areaOf(List<Offset> ring) {
  var sum = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum.abs() / 2;
}

// 경계까지 거리가 가장 먼 내부점(polylabel). 사각형 격자를 반씩 쪼개며
// 더 나아질 여지가 정밀도 이하인 칸은 버린다
Offset labelPointOf(List<List<Offset>> rings, {double precision = 1}) {
  final bounds = boundsOf(rings.first);
  final cellSize = math.min(bounds.width, bounds.height);
  if (cellSize == 0) return bounds.topLeft;

  _Cell cell(double x, double y, double half) =>
      _Cell(x, y, half, _signedDistance(Offset(x, y), rings));

  final queue = <_Cell>[
    for (var x = bounds.left; x < bounds.right; x += cellSize)
      for (var y = bounds.top; y < bounds.bottom; y += cellSize)
        cell(x + cellSize / 2, y + cellSize / 2, cellSize / 2),
  ];
  var best = cell(bounds.center.dx, bounds.center.dy, 0);
  while (queue.isNotEmpty) {
    // 칸 수가 수백 개 수준이라 우선순위 큐 대신 선형 탐색으로 최댓값을 꺼낸다
    var index = 0;
    for (var i = 1; i < queue.length; i++) {
      if (queue[i].potential > queue[index].potential) index = i;
    }
    final current = queue.removeAt(index);
    if (current.distance > best.distance) best = current;
    if (current.potential - best.distance <= precision) continue;
    final half = current.half / 2;
    queue
      ..add(cell(current.x - half, current.y - half, half))
      ..add(cell(current.x + half, current.y - half, half))
      ..add(cell(current.x - half, current.y + half, half))
      ..add(cell(current.x + half, current.y + half, half));
  }
  return Offset(best.x, best.y);
}

class _Cell {
  _Cell(this.x, this.y, this.half, this.distance)
    : potential = distance + half * math.sqrt2;

  final double x;
  final double y;
  final double half;
  final double distance;
  // 이 칸 안에서 나올 수 있는 최대 거리
  final double potential;
}

// 폴리곤 경계까지의 거리. 내부(구멍 밖)면 양수, 외부면 음수
double _signedDistance(Offset point, List<List<Offset>> rings) {
  var inside = false;
  var minSquared = double.infinity;
  for (final ring in rings) {
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final a = ring[i];
      final b = ring[j];
      if ((a.dy > point.dy) != (b.dy > point.dy) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
      minSquared = math.min(minSquared, _segmentDistanceSquared(point, a, b));
    }
  }
  return (inside ? 1 : -1) * math.sqrt(minSquared);
}

double _segmentDistanceSquared(Offset p, Offset a, Offset b) {
  final d = b - a;
  final lengthSquared = d.distanceSquared;
  final t = lengthSquared == 0
      ? 0.0
      : (((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / lengthSquared).clamp(
          0.0,
          1.0,
        );
  return (p - (a + d * t)).distanceSquared;
}
