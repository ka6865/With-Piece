import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/map_data/map_asset.dart';

void main() {
  final asset = MapAsset.parse('''
    {"version":1,"mainlandBbox":[0,0,1,1],"insets":[],"features":[
      {"id":"11","name":"서울","parentId":null,"polygons":[[[[0,0],[1,0],[1,1],[0,1],[0,0]]]]}
    ]}
  ''');

  test('같은 asset과 크기는 레이아웃을 재사용하고 최근 8개만 유지한다', () {
    const firstSize = Size(100, 100);
    const secondSize = Size(101, 100);
    final first = PuzzleLayout.cached(asset: asset, size: firstSize);
    final second = PuzzleLayout.cached(asset: asset, size: secondSize);
    expect(PuzzleLayout.cached(asset: asset, size: firstSize), same(first));

    for (var width = 1; width <= 7; width++) {
      PuzzleLayout.cached(asset: asset, size: Size(width.toDouble(), 100));
    }

    expect(PuzzleLayout.cached(asset: asset, size: firstSize), same(first));
    expect(
      PuzzleLayout.cached(asset: asset, size: secondSize),
      isNot(same(second)),
    );
  });
}
