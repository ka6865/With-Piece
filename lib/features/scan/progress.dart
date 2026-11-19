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

// 홈 작은 지도에서 맞춰 넣을 조각(커플 디자인 4.7). 기준이 없으면(첫 설치·새 기기)
// 연출하지 않는다
Set<String> newlyFilled(Set<String>? seen, Set<String> current) =>
    seen == null ? const {} : current.difference(seen);

// 여행 확인 직후 문구. 확인 전 채운 조각을 모르면 조각 수를 말하지 않는다
String confirmedTripMessage(
  Set<String>? filledBefore,
  Iterable<String> regionIds,
) {
  final added = filledBefore == null
      ? 0
      : regionIds.toSet().difference(filledBefore).length;
  return added == 0 ? '여행을 담았어요' : '우리의 조각이 $added개 늘었어요';
}
