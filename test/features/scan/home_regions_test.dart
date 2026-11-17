import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/scan/home_regions.dart';
import 'package:woori_piece/features/scan/photo_days.dart';

List<PhotoDay> daysIn(String regionId, int count) => [
  for (var i = 0; i < count; i++) PhotoDay(DateTime(2026, 1, 1 + i), regionId),
];

void main() {
  test('겹친 서로 다른 날이 기준 이상이면 생활권이다', () {
    final matched = [...daysIn('11140', 10), ...daysIn('32060', 9)];
    expect(homeRegions(matched, const {}), {'11140'});
  });

  test('덮어쓰기가 자동 분류보다 우선한다', () {
    final matched = [...daysIn('11140', 12), ...daysIn('32060', 2)];
    expect(
      homeRegions(matched, const {
        '11140': OverrideKind.travel,
        '11230': OverrideKind.home,
      }),
      {'11230'},
    );
  });
}
