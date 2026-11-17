import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/map/painter/map_projection.dart';
import 'package:woori_piece/map_data/map_asset.dart';

void main() {
  test('본토 중간위도 보정과 네 꼭짓점이 맞다', () {
    const bbox = GeoBbox(124.60972, 33.11252, 129.58443, 38.6136);
    final p = MapProjection.fit(bbox: bbox, size: const Size(390, 600));
    expect(p.cosLat, closeTo(0.810, 0.0005));
    expect(p.project(GeoPoint(bbox.west, bbox.north)), Offset(p.dx, p.dy));
    final br = p.project(GeoPoint(bbox.east, bbox.south));
    expect(br.dx, closeTo(390 - p.dx, 1e-6));
    expect(br.dy, closeTo(600 - p.dy, 1e-6));
  });
}
