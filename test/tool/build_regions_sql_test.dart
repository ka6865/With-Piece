import 'package:flutter_test/flutter_test.dart';

import '../../tool/build_map_assets.dart' show readJson;
import '../../tool/build_regions_sql.dart';

void main() {
  test('애셋에서 regions 246행을 만든다', () {
    final sql = buildRegionsSql(
      provinces: readJson('assets/map/provinces_v1.json'),
      regions: readJson('assets/map/regions_v1.json'),
    );
    final rows = RegExp(r"^\s*\('", multiLine: true).allMatches(sql).length;
    expect(rows, 246);
    expect(sql, contains("('38-38111', '창원시', '38', 2)"));
    expect(sql, contains("('32400', '고성군', '32', 2)"));
    expect(sql, contains("('38340', '고성군', '38', 2)"));
    expect(sql, contains("('11', '서울특별시', null, 1)"));
    // 시도가 먼저 들어가야 parent_id 외래키가 성립한다
    expect(sql.indexOf("('39', "), lessThan(sql.indexOf("('11010', ")));
  });

  test('작은따옴표를 이스케이프한다', () {
    expect(sqlLiteral("O'Neil"), "'O''Neil'");
  });
}
