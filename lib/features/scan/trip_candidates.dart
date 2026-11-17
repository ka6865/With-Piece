import 'photo_days.dart';

// 양 끝을 포함하는 날짜 구간
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);

  int get nights => _dayNumber(end) - _dayNumber(start);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

class TripCandidate {
  const TripCandidate({
    required this.range,
    required this.regionIds,
    required this.title,
  });

  final DateRange range;
  // 처음 겹친 순서
  final List<String> regionIds;
  final String title;
}

// 생활권이 아닌 겹친 날을 연속 구간으로 묶어 여행 후보를 만든다(설계 5.4).
// 이미 확인하거나 버린 여행 기간에 걸친 날은 빼므로 같은 후보가 돌아오지 않는다
List<TripCandidate> tripCandidates(
  Iterable<PhotoDay> matched, {
  required Set<String> home,
  required List<DateRange> existing,
  required Map<String, String> regionNames,
}) {
  final byDay = <DateTime, List<String>>{};
  for (final day in matched) {
    if (home.contains(day.regionId)) continue;
    if (existing.any((range) => range.contains(day.day))) continue;
    final regions = byDay.putIfAbsent(day.day, () => []);
    if (!regions.contains(day.regionId)) regions.add(day.regionId);
  }
  final days = byDay.keys.toList()..sort();

  final candidates = <TripCandidate>[];
  var start = 0;
  for (var i = 1; i <= days.length; i++) {
    final continues =
        i < days.length && _dayNumber(days[i]) - _dayNumber(days[i - 1]) == 1;
    if (continues) continue;
    final regionIds = <String>[];
    for (final day in days.sublist(start, i)) {
      for (final region in byDay[day]!) {
        if (!regionIds.contains(region)) regionIds.add(region);
      }
    }
    final range = DateRange(days[start], days[i - 1]);
    candidates.add(
      TripCandidate(
        range: range,
        regionIds: regionIds,
        title: candidateTitle(regionIds, range, regionNames),
      ),
    );
    start = i;
  }
  return candidates.reversed.toList();
}

// 규칙 기반 제목(설계 16.5). 예: "속초시 고성군 1박 2일"
String candidateTitle(
  List<String> regionIds,
  DateRange range,
  Map<String, String> regionNames,
) {
  final names = regionIds.map((id) => regionNames[id] ?? id).join(' ');
  return range.nights == 0
      ? names
      : '$names ${range.nights}박 ${range.nights + 1}일';
}

// 서머타임 등으로 하루가 24시간이 아니어도 날짜 차이를 정확히 세려고 UTC로 센다
int _dayNumber(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day).millisecondsSinceEpoch ~/
    Duration.millisecondsPerDay;
