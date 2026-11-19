import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/map/view/province_map_page.dart';
import 'package:woori_piece/map_data/map_asset.dart';

void main() {
  final regions = MapAsset.parse(
    File('assets/map/regions_v1.json').readAsStringSync(),
  );

  test('시도 및 조각 지도 애셋을 다시 만들지 않고 재사용한다', () {
    final province = provinceAssetOf(regions, '32');
    final shape = regionShapeAssetOf(regions, '32060');

    expect(regionShapeAssetOf(regions, '32060'), same(shape));
    expect(provinceAssetOf(regions, '32'), same(province));

    for (final feature
        in regions.features.where((f) => f.id != '32060').take(31)) {
      regionShapeAssetOf(regions, feature.id);
    }

    expect(provinceAssetOf(regions, '32'), same(province));
    expect(regionShapeAssetOf(regions, '32060'), isNot(same(shape)));
  });
}
