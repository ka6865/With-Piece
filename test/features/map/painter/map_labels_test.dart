import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/features/map/painter/puzzle_painter.dart';
import 'package:woori_piece/map_data/map_asset.dart';

void main() {
  for (final (file, count) in [('regions_v1', 229), ('provinces_v1', 17)]) {
    test('$file의 모든 조각 이름 위치가 자기 조각으로 판정된다', () {
      final asset = MapAsset.parse(
        File('assets/map/$file.json').readAsStringSync(),
      );
      final layout = PuzzleLayout.build(
        asset: asset,
        size: const Size(390, 600),
      );
      expect(layout.labelPoints.length, count);
      final hitTester = layout.hitTester;
      final wrong = [
        for (final MapEntry(key: id, value: point)
            in layout.labelPoints.entries)
          if (hitTester.hitTest(point) != id) id,
      ];
      expect(wrong, isEmpty);
    });
  }

  test('시도 애셋의 본토에 17개 시도가 모두 그려지고 경북 본토는 탭된다', () {
    final asset = MapAsset.parse(
      File('assets/map/provinces_v1.json').readAsStringSync(),
    );
    final layout = PuzzleLayout.build(asset: asset, size: const Size(390, 600));
    final mainland = layout.polygons.where((p) => p.insetId == null).toList();
    expect(mainland.map((p) => p.regionId).toSet().length, 17);
    final gyeongbuk = mainland.where((p) => p.regionId == '37').toList()
      ..sort((a, b) => b.area.compareTo(a.area));
    final point = labelPointOf(gyeongbuk.first.rings);
    expect(layout.hitTester.hitTest(point), '37');
    expect(layout.insetRects.values.any((r) => r.contains(point)), isFalse);
  });

  test('이름 위치는 경계에서 가장 먼 내부점이다', () {
    // 정사각형은 중앙
    const square = [
      [
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
        Offset(0, 0),
      ],
    ];
    final center = labelPointOf(square);
    expect(center.dx, closeTo(50, 1));
    expect(center.dy, closeTo(50, 1));

    // 위쪽이 넓고 길쭉한 꼬리가 달린 모양은 넓은 몸통 안쪽. 수평 구간 최대폭
    // 기준이면 몸통 윗변 근처에 붙는다
    const body = [
      [
        Offset(0, 0),
        Offset(200, 0),
        Offset(200, 120),
        Offset(110, 120),
        Offset(110, 400),
        Offset(90, 400),
        Offset(90, 120),
        Offset(0, 120),
        Offset(0, 0),
      ],
    ];
    final point = labelPointOf(body);
    expect(point.dy, closeTo(60, 2));
    expect(point.dx, closeTo(100, 40));
  });

  test('구멍 안에는 이름을 두지 않는다', () {
    const ring = [
      [
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
        Offset(0, 0),
      ],
      [
        Offset(30, 30),
        Offset(70, 30),
        Offset(70, 70),
        Offset(30, 70),
        Offset(30, 30),
      ],
    ];
    final point = labelPointOf(ring);
    final inHole =
        point.dx > 30 && point.dx < 70 && point.dy > 30 && point.dy < 70;
    expect(inHole, isFalse);
  });

  test('시도명을 규칙으로 줄인다', () {
    final provinces = MapAsset.parse(
      File('assets/map/provinces_v1.json').readAsStringSync(),
    );
    expect(provinces.features.map((f) => shortRegionName(f.name)).toList(), [
      '서울',
      '부산',
      '대구',
      '인천',
      '광주',
      '대전',
      '울산',
      '세종',
      '경기',
      '강원',
      '충북',
      '충남',
      '전북',
      '전남',
      '경북',
      '경남',
      '제주',
    ]);
    expect(shortRegionName('고성군'), '고성군');
    expect(shortRegionName('창원시'), '창원시');
  });
}
