import 'dart:math' as math;
import 'dart:ui';

import '../../../data/repositories/region_cover_repository.dart';

// 저장된 구도를 화면에서 사진을 그릴 사각형으로 바꾼다. 확대면 사진이 조각 bbox를
// 덮도록(빈 틈이 보이지 않게), 축소면 사진이 bbox 안에 머물도록 위치를 조인다
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
  final s = base * scale.clamp(minCoverScale, maxCoverScale);
  final w = image.width * s;
  final h = image.height * s;
  final left = _between(
    bounds.center.dx - centerX * w,
    bounds.left,
    bounds.right - w,
  );
  final top = _between(
    bounds.center.dy - centerY * h,
    bounds.top,
    bounds.bottom - h,
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
  bool blackBackground = false,
}) {
  final base = math.max(
    bounds.width / image.width,
    bounds.height / image.height,
  );
  return RegionCover(
    regionId: regionId,
    photoId: photoId,
    scale: (placed.width / image.width / base).clamp(
      minCoverScale,
      maxCoverScale,
    ),
    centerX: ((bounds.center.dx - placed.left) / placed.width).clamp(-1, 2),
    centerY: ((bounds.center.dy - placed.top) / placed.height).clamp(-1, 2),
    blackBackground: blackBackground,
  );
}

// region_covers 검사 제약과 같은 범위
const minCoverScale = 0.25;
const maxCoverScale = 8.0;

// 두 끝 중 어느 쪽이 큰지와 관계없이 그 사이로 조인다
double _between(double value, double a, double b) =>
    value.clamp(math.min(a, b), math.max(a, b));
