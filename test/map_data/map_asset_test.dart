import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/map_data/map_asset.dart';

void main() {
  final regions = MapAsset.parse(
    File('assets/map/regions_v1.json').readAsStringSync(),
  );

  test('시군구 애셋의 복잡한 형상을 보존한다', () {
    expect(regions.features.length, 229);
    expect(regions.byId('36480')!.polygons.length, 263);
    expect(regions.byId('36480')!.pointCount, 3962);
    expect(
      regions.features.where((f) => f.name == '고성군').map((f) => f.id),
      containsAll(['32400', '38340']),
    );
    final holeCount = regions.features
        .expand((f) => f.polygons)
        .where((poly) => poly.length > 1)
        .length;
    expect(holeCount, 6);
  });

  test('시도별 조각 수가 설계 문서 3장의 분모와 같다', () {
    expect(regions.pieceCountByProvince(), {
      '11': 25,
      '21': 16,
      '22': 8,
      '23': 10,
      '24': 5,
      '25': 5,
      '26': 5,
      '29': 1,
      '31': 31,
      '32': 18,
      '33': 11,
      '34': 15,
      '35': 14,
      '36': 22,
      '37': 23,
      '38': 18,
      '39': 2,
    });
  });

  test('시도 애셋은 parentId 없이 17개 시도와 인셋을 갖는다', () {
    final provinces = MapAsset.parse(
      File('assets/map/provinces_v1.json').readAsStringSync(),
    );
    expect(provinces.features.length, 17);
    expect(provinces.features.every((f) => f.parentId == null), isTrue);
    expect(provinces.insets.map((i) => i.regionId), ['37', '37']);
  });

  test('지원하지 않는 버전을 거부한다', () {
    expect(
      () => MapAsset.parse(
        '{"version":2,"mainlandBbox":[],"insets":[],"features":[]}',
      ),
      throwsFormatException,
    );
  });
}
