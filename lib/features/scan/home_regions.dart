import 'photo_days.dart';

enum OverrideKind { home, travel }

// 겹친 서로 다른 날이 기준 이상인 조각을 생활권으로 본다(설계 5.3).
// 두 사람 기기가 같은 입력으로 같은 결과를 내도록 순수 함수로 둔다
Set<String> homeRegions(
  Iterable<PhotoDay> matched,
  Map<String, OverrideKind> overrides, {
  int minDays = 10,
}) {
  final days = <String, Set<DateTime>>{};
  for (final day in matched) {
    days.putIfAbsent(day.regionId, () => {}).add(day.day);
  }
  return {
    for (final MapEntry(key: region, value: dates) in days.entries)
      if (dates.length >= minDays && overrides[region] != OverrideKind.travel)
        region,
    for (final MapEntry(key: region, value: kind) in overrides.entries)
      if (kind == OverrideKind.home) region,
  };
}
