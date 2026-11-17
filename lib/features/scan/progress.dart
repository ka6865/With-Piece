import '../../data/repositories/trip_repository.dart';

// 칠해진 조각 = 확인된 여행의 조각 ∪ 생활권(설계 6.3). 버린 여행은 세지 않는다
Set<String> filledRegionIds(Iterable<Trip> trips, Set<String> home) => {
  for (final trip in trips)
    if (trip.status == TripStatus.confirmed) ...trip.regionIds,
  ...home,
};

// 진행률 분자. 분모는 번들 애셋의 pieceCountByProvince()다
Map<String, int> filledCountByProvince(
  Set<String> filled,
  Map<String, String> parentOf,
) {
  final counts = <String, int>{};
  for (final id in filled) {
    final parent = parentOf[id];
    if (parent != null) counts[parent] = (counts[parent] ?? 0) + 1;
  }
  return counts;
}
