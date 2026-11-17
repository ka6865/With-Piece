import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/build_map_assets.dart';

void main() {
  test('시군구 전처리가 확정값을 재현한다', () {
    final topo = readJson(
      'tool/map_source/skorea-municipalities-2018-topo-simple.json',
    );
    final asset = buildMapAsset(topo, kind: AssetKind.region);
    expect(asset.features.length, 229);
    expect(asset.pointCount, 79868);
    expect(asset.mainlandBbox.rounded5, [
      124.60972,
      33.11252,
      129.58443,
      38.6136,
    ]);
    expect(asset.insets[0].polygonIndexes, [2, 3, 4]);
    expect(asset.insets[1].polygonIndexes, [0, 1]);
    expect(utf8.encode(asset.toJsonString()).length, 1680480);
  });

  test('시도 전처리가 확정값을 재현한다', () {
    final topo = readJson(
      'tool/map_source/skorea-provinces-2018-topo-simple.json',
    );
    final asset = buildMapAsset(topo, kind: AssetKind.province);
    expect(asset.features.length, 17);
    expect(asset.pointCount, 30623);
    expect(asset.insets[0].regionId, '37');
    expect(asset.insets[0].polygonIndexes, [7]);
    expect(asset.insets[1].polygonIndexes, [5, 6]);
    expect(utf8.encode(asset.toJsonString()).length, 637805);
  });
}
