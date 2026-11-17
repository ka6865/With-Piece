// 번들 지도 애셋에서 regions 기준 데이터 마이그레이션을 만든다.
// 지역 코드를 손으로 적지 않기 위해서다(AGENTS.md 3.1).
import 'dart:io';

import 'build_map_assets.dart' show readJson;

String sqlLiteral(String value) => "'${value.replaceAll("'", "''")}'";

String buildRegionsSql({
  required Map<String, dynamic> provinces,
  required Map<String, dynamic> regions,
}) {
  List<Map<String, dynamic>> featuresOf(Map<String, dynamic> asset) =>
      (asset['features'] as List).cast<Map<String, dynamic>>();
  final rows = [
    for (final f in featuresOf(provinces))
      "(${sqlLiteral(f['id'] as String)}, ${sqlLiteral(f['name'] as String)}, null, 1)",
    for (final f in featuresOf(regions))
      "(${sqlLiteral(f['id'] as String)}, ${sqlLiteral(f['name'] as String)}, "
          "${sqlLiteral(f['parentId'] as String)}, 2)",
  ];
  return [
    '-- 생성 파일. 직접 수정하지 않는다. dart run tool/build_regions_sql.dart 로 재생성한다',
    'insert into public.regions (id, name, parent_id, depth) values',
    rows.map((r) => '  $r').join(',\n'),
    ';',
    '',
  ].join('\n');
}

void main() {
  stdout.write(
    buildRegionsSql(
      provinces: readJson('assets/map/provinces_v1.json'),
      regions: readJson('assets/map/regions_v1.json'),
    ),
  );
}
