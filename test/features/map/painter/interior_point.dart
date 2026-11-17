import 'dart:ui';

import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/features/map/painter/region_hit_tester.dart';

// 외곽 링 평균점이 외곽 안·구멍 밖이면 그 점을, 아니면 bbox를 60등분한
// 수평 주사선에서 교차점 쌍의 중점을 찾는다
Offset? interiorPointOf(List<List<Offset>> rings) {
  bool valid(Offset p) =>
      isInside(p, rings.first) &&
      !rings.skip(1).any((hole) => isInside(p, hole));
  final outer = rings.first;
  final mean = outer.reduce((a, b) => a + b) / outer.length.toDouble();
  if (valid(mean)) return mean;
  final bounds = boundsOf(outer);
  for (var i = 1; i < 60; i++) {
    final y = bounds.top + bounds.height * i / 60;
    final xs = <double>[];
    for (final ring in rings) {
      for (var j = 0; j < ring.length; j++) {
        final a = ring[j];
        final b = ring[(j + 1) % ring.length];
        if ((a.dy > y) != (b.dy > y)) {
          xs.add((b.dx - a.dx) * (y - a.dy) / (b.dy - a.dy) + a.dx);
        }
      }
    }
    xs.sort();
    for (var k = 0; k + 1 < xs.length; k += 2) {
      final p = Offset((xs[k] + xs[k + 1]) / 2, y);
      if (valid(p)) return p;
    }
  }
  return null;
}
