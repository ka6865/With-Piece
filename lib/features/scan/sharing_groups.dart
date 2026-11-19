import 'photo_days.dart';

// 비교할 기록 목록의 한 번 다녀온 기간. 같은 조각의 연속된 날짜다
class SharingVisit {
  const SharingVisit(this.days, this.photoCount);

  // 날짜 오름차순
  final List<PhotoDay> days;
  final int photoCount;

  DateTime get start => days.first.day;
  DateTime get end => days.last.day;
}

class SharingRegionGroup {
  const SharingRegionGroup(this.regionId, this.visits, {this.isHome = false});

  final String regionId;
  // 최근에 다녀온 번이 앞
  final List<SharingVisit> visits;
  final bool isHome;

  int get dayCount => visits.fold(0, (sum, v) => sum + v.days.length);
  Iterable<PhotoDay> get days => visits.expand((v) => v.days);
}

// 7년치 기록도 고를 수 있게 지역 → 다녀온 번 → 날짜로 묶는다. 하루라도 비면 다른
// 번이며, 여행 후보 묶기(설계 5.4)와 같은 기준이다. 사는 곳은 맨 아래에 둔다
List<SharingRegionGroup> groupSharingDays(
  Map<PhotoDay, int> days, {
  String? homeRegionId,
}) {
  final byRegion = <String, List<PhotoDay>>{};
  for (final day in days.keys) {
    byRegion.putIfAbsent(day.regionId, () => []).add(day);
  }
  final groups = <SharingRegionGroup>[];
  for (final MapEntry(key: region, value: list) in byRegion.entries) {
    list.sort((a, b) => a.day.compareTo(b.day));
    final visits = <List<PhotoDay>>[];
    for (final day in list) {
      final last = visits.lastOrNull?.last;
      // 서머타임 없는 날짜 차이로 이어짐을 본다
      if (last != null &&
          DateTime.utc(day.day.year, day.day.month, day.day.day)
                  .difference(
                    DateTime.utc(last.day.year, last.day.month, last.day.day),
                  )
                  .inDays ==
              1) {
        visits.last.add(day);
      } else {
        visits.add([day]);
      }
    }
    groups.add(
      SharingRegionGroup(region, [
        for (final v in visits.reversed)
          SharingVisit(v, v.fold(0, (sum, d) => sum + days[d]!)),
      ], isHome: region == homeRegionId),
    );
  }
  groups.sort((a, b) {
    if (a.isHome != b.isHome) return a.isHome ? 1 : -1;
    return b.visits.first.end.compareTo(a.visits.first.end);
  });
  return groups;
}

// 서로 다른 날이 가장 많은 조각. 사진 수가 아니라 날 수로 봐야 여행지 하루 몰아
// 찍은 사진보다 매일 찍히는 동네가 앞선다
String? suggestHomeRegion(Map<PhotoDay, int> days) {
  final counts = <String, int>{};
  for (final day in days.keys) {
    counts[day.regionId] = (counts[day.regionId] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
