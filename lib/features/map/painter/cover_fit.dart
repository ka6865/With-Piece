import 'dart:math' as math;
import 'dart:ui';

import '../../../data/repositories/region_cover_repository.dart';

// 저장된 구도를 화면에서 사진을 그릴 사각형으로 바꾼다. 사진은 언제나 조각 bbox를
// 덮도록 위치를 조인다(빈 틈이 보이지 않게)
Rect coverImageRect({
  required Rect bounds,
  required Size image,
  required double scale,
  required double centerX,
  required double centerY,
}) {
  final base = math.max(
    bounds.width / image.width,
    bounds.height / image.height,
  );
  final s = base * math.max(1, scale);
  final w = image.width * s;
  final h = image.height * s;
  final left = (bounds.center.dx - centerX * w).clamp(
    bounds.right - w,
    bounds.left,
  );
  final top = (bounds.center.dy - centerY * h).clamp(
    bounds.bottom - h,
    bounds.top,
  );
  return Rect.fromLTWH(left, top, w, h);
}

// 구도 맞춤 화면에서 사진을 놓은 사각형을 저장 값으로 되돌린다
RegionCover coverFromRect({
  required String regionId,
  required String photoId,
  required Rect bounds,
  required Size image,
  required Rect placed,
}) {
  final base = math.max(
    bounds.width / image.width,
    bounds.height / image.height,
  );
  return RegionCover(
    regionId: regionId,
    photoId: photoId,
    scale: (placed.width / image.width / base).clamp(1, 8),
    centerX: ((bounds.center.dx - placed.left) / placed.width).clamp(0, 1),
    centerY: ((bounds.center.dy - placed.top) / placed.height).clamp(0, 1),
  );
}
