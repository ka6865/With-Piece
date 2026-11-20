import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/map/painter/cover_fit.dart';

void main() {
  const image = Size(4000, 3000);

  test('기본 구도는 사진 가운데로 조각을 꼭 맞게 덮는다', () {
    const bounds = Rect.fromLTWH(10, 20, 100, 100);
    final rect = coverImageRect(
      bounds: bounds,
      image: image,
      scale: 1,
      centerX: 0.5,
      centerY: 0.5,
    );
    expect(rect.height, closeTo(100, 1e-9));
    expect(rect.center.dx, closeTo(bounds.center.dx, 1e-9));
    expect(rect.top, closeTo(bounds.top, 1e-9));
  });

  test('저장한 구도는 다른 화면 크기에서도 같은 영역을 보인다', () {
    const small = Rect.fromLTWH(0, 0, 80, 120);
    const placed = Rect.fromLTWH(-150, -40, 320, 240);
    final cover = coverFromRect(
      regionId: 'r',
      photoId: 'p',
      bounds: small,
      image: image,
      placed: placed,
    );
    // 같은 비율로 3배 큰 화면에 그리면 사각형도 3배다
    const large = Rect.fromLTWH(0, 0, 240, 360);
    final rect = coverImageRect(
      bounds: large,
      image: image,
      scale: cover.scale,
      centerX: cover.centerX,
      centerY: cover.centerY,
    );
    expect(rect.left, closeTo(placed.left * 3, 1e-6));
    expect(rect.top, closeTo(placed.top * 3, 1e-6));
    expect(rect.width, closeTo(placed.width * 3, 1e-6));
  });

  test('사진이 조각을 벗어나 빈 틈이 생기는 위치는 조인다', () {
    const bounds = Rect.fromLTWH(0, 0, 100, 100);
    final rect = coverImageRect(
      bounds: bounds,
      image: image,
      scale: 1,
      centerX: 0,
      centerY: 0.5,
    );
    expect(rect.left, 0);
  });

  test('축소하면 사진이 조각 안에 머물고 구도와 여백 색이 되돌아온다', () {
    const bounds = Rect.fromLTWH(0, 0, 100, 100);
    // 기본 배율(높이 100)의 절반, 왼쪽 위에 붙인다
    const placed = Rect.fromLTWH(0, 0, 4000 / 60, 50);
    final cover = coverFromRect(
      regionId: 'r',
      photoId: 'p',
      bounds: bounds,
      image: image,
      placed: placed,
      blackBackground: true,
    );
    expect(cover.scale, closeTo(0.5, 1e-9));
    expect(cover.blackBackground, isTrue);
    final rect = coverImageRect(
      bounds: bounds,
      image: image,
      scale: cover.scale,
      centerX: cover.centerX,
      centerY: cover.centerY,
    );
    expect(rect.left, closeTo(0, 1e-9));
    expect(rect.top, closeTo(0, 1e-9));
    expect(rect.height, closeTo(50, 1e-9));
    // 조각 밖으로 끌어도 안쪽에 붙는다
    final out = coverImageRect(
      bounds: bounds,
      image: image,
      scale: 0.5,
      centerX: 2,
      centerY: -1,
    );
    expect(out.left, closeTo(0, 1e-9));
    expect(out.bottom, closeTo(100, 1e-9));
  });

  test('배율은 0.25배 아래로 내려가지 않는다', () {
    final cover = coverFromRect(
      regionId: 'r',
      photoId: 'p',
      bounds: const Rect.fromLTWH(0, 0, 100, 100),
      image: image,
      placed: const Rect.fromLTWH(40, 40, 4, 3),
    );
    expect(cover.scale, minCoverScale);
  });
}
