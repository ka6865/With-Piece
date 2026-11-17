import 'dart:math' as math;
import 'dart:ui';

import '../../../map_data/map_asset.dart';

// 등거리 선형 투영에 cos(중간위도) 종횡비 보정을 적용한다(설계 문서 4.3)
class MapProjection {
  const MapProjection._({
    required this.bbox,
    required this.size,
    required this.cosLat,
    required this.scale,
    required this.dx,
    required this.dy,
  });

  factory MapProjection.fit({required GeoBbox bbox, required Size size}) {
    final cosLat = math.cos((bbox.south + bbox.north) / 2 * math.pi / 180);
    final spanX = (bbox.east - bbox.west) * cosLat;
    final spanY = bbox.north - bbox.south;
    final scale = math.min(size.width / spanX, size.height / spanY);
    return MapProjection._(
      bbox: bbox,
      size: size,
      cosLat: cosLat,
      scale: scale,
      dx: (size.width - spanX * scale) / 2,
      dy: (size.height - spanY * scale) / 2,
    );
  }

  final GeoBbox bbox;
  final Size size;
  final double cosLat;
  final double scale;
  final double dx;
  final double dy;

  Offset project(GeoPoint p) => Offset(
    dx + (p.lon - bbox.west) * cosLat * scale,
    dy + (bbox.north - p.lat) * scale,
  );
}
