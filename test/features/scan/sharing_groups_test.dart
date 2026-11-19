import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/sharing_groups.dart';

PhotoDay d(String region, int month, int day) =>
    PhotoDay(DateTime(2025, month, day), region);

void main() {
  test('지역 아래를 연속된 날짜로 다녀온 번을 나눈다', () {
    final groups = groupSharingDays({
      d('jeju', 5, 1): 40,
      d('jeju', 5, 2): 50,
      d('jeju', 5, 3): 30,
      // 하루가 비면 다른 번이다
      d('jeju', 5, 5): 10,
      d('sokcho', 8, 10): 20,
    });
    final jeju = groups.singleWhere((g) => g.regionId == 'jeju');
    expect(jeju.visits.length, 2);
    // 최근에 다녀온 번이 위
    expect(jeju.visits.first.days, [d('jeju', 5, 5)]);
    expect(jeju.visits.last.days, [
      d('jeju', 5, 1),
      d('jeju', 5, 2),
      d('jeju', 5, 3),
    ]);
    expect(jeju.visits.last.photoCount, 120);
    expect(jeju.dayCount, 4);
  });

  test('최근에 다녀온 지역이 위, 사는 곳은 맨 아래다', () {
    final groups = groupSharingDays({
      d('osan', 9, 1): 3,
      d('jeju', 5, 1): 1,
      d('sokcho', 8, 10): 2,
    }, homeRegionId: 'osan');
    expect(groups.map((g) => g.regionId), ['sokcho', 'jeju', 'osan']);
    expect(groups.last.isHome, isTrue);
  });

  test('사는 곳 추천은 서로 다른 날이 가장 많은 조각이다', () {
    expect(
      suggestHomeRegion({
        d('osan', 1, 1): 1,
        d('osan', 1, 2): 1,
        d('osan', 1, 3): 1,
        d('jeju', 5, 1): 300,
      }),
      'osan',
    );
    expect(suggestHomeRegion({}), isNull);
  });

  test('같은 기간에 붙어 다닌 다른 조각을 함께 묶는다', () {
    final groups = groupSharingDays({
      d('sokcho', 10, 3): 30,
      d('goseong', 10, 4): 10,
      // 매일 찍히는 곳(10일 이상)은 다른 여행을 끌어오지 않게 묶지 않는다
      for (var day = 1; day <= 12; day++) d('suwon', 10, day): 1,
      d('jeju', 5, 1): 5,
    }, homeRegionId: 'osan');
    final sokcho = groups.singleWhere((g) => g.regionId == 'sokcho');
    final visit = sokcho.visits.single;
    expect(visit.linkedRegionIds, ['goseong']);
    expect(visit.allDays.toSet(), {d('sokcho', 10, 3), d('goseong', 10, 4)});
    final goseong = groups.singleWhere((g) => g.regionId == 'goseong');
    expect(goseong.visits.single.linkedRegionIds, ['sokcho']);
    final jeju = groups.singleWhere((g) => g.regionId == 'jeju');
    expect(jeju.visits.single.linkedRegionIds, isEmpty);
  });
}
