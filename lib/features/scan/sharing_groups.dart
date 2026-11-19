import 'photo_days.dart';

// 비교할 기록 목록의 한 번 다녀온 기간. 같은 조각의 연속된 날짜다
class SharingVisit {
  const SharingVisit(
    this.days,
    this.photoCount, {
    this.linkedRegionIds = const [],
    this.linkedDays = const [],
  });

  // 날짜 오름차순
  final List<PhotoDay> days;
  final int photoCount;
  // 같은 여행으로 붙어 다닌 다른 조각(속초 1박 2일의 고성). 고르면 함께 고른다
  final List<String> linkedRegionIds;
  final List<PhotoDay> linkedDays;

  Iterable<PhotoDay> get allDays => [...days, ...linkedDays];

  // 서로 다른 날짜 수. 같은 날 두 조각에 있었어도 하루다
  int get dateCount => {for (final d in allDays) d.day}.length;

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
  final trips = _tripChains(days.keys, homeRegionId: homeRegionId);
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
      // 같은 여행에 속하면 중간에 다른 조각만 찍힌 날이 있어도 한 번이다
      if (last != null &&
          trips[last] != null &&
          identical(trips[last], trips[day])) {
        visits.last.add(day);
        continue;
      }
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
          () {
            final linked = [
              ...?trips[v.first]?.where((d) => d.regionId != region),
            ];
            return SharingVisit(
              v,
              v.fold(0, (sum, d) => sum + days[d]!),
              linkedRegionIds: {for (final d in linked) d.regionId}.toList(),
              linkedDays: linked,
            );
          }(),
      ], isHome: region == homeRegionId),
    );
  }
  groups.sort((a, b) {
    if (a.isHome != b.isHome) return a.isHome ? 1 : -1;
    return b.visits.first.end.compareTo(a.visits.first.end);
  });
  return groups;
}

// 여행 후보 묶기(설계 5.4)처럼 연속된 날짜를 조각과 상관없이 한 여행으로 잇는다.
// 사는 곳과 서로 다른 날이 10일 이상인 조각(생활권 기준, 설계 5.3)은 매일 찍혀
// 모든 여행을 하나로 이어 버리므로 빼고 잇는다. 날짜·조각별로 그 여행의 날들을 돌려준다
Map<PhotoDay, List<PhotoDay>> _tripChains(
  Iterable<PhotoDay> days, {
  String? homeRegionId,
}) {
  final dayCount = <String, int>{};
  for (final d in days) {
    dayCount[d.regionId] = (dayCount[d.regionId] ?? 0) + 1;
  }
  final travel = [
    for (final d in days)
      if (d.regionId != homeRegionId && dayCount[d.regionId]! < 10) d,
  ]..sort((a, b) => a.day.compareTo(b.day));
  final chains = <List<PhotoDay>>[];
  for (final d in travel) {
    final last = chains.lastOrNull?.last.day;
    if (last != null && _daysBetween(last, d.day) <= 1) {
      chains.last.add(d);
    } else {
      chains.add([d]);
    }
  }
  return {
    for (final chain in chains)
      for (final d in chain) d: chain,
  };
}

int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

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
