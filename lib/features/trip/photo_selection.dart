// 내 사진첩의 사진 한 장. assetId는 기기 안에서만 쓰고 서버로 보내지 않는다(설계 5.1)
class LocalPhoto {
  const LocalPhoto({
    required this.assetId,
    required this.takenAt,
    required this.regionId,
  });

  final String assetId;
  final DateTime takenAt;
  // 위치가 없거나 조각 밖이면 null. 목록에는 보이되 기본 선택에서 빠진다
  final String? regionId;
}

// 설계 8.0의 초기값. 3단계 실사용으로 조정한다
const defaultPhotosPerRegion = 6;

// 조각마다 촬영 시각이 고르게 퍼지도록 N장을 기본 선택한다(설계 8.0)
// regions가 주어지면 그 조각(여행에 포함된 조각)의 사진만 고른다
Set<String> defaultSelection(
  Iterable<LocalPhoto> photos, {
  int perRegion = defaultPhotosPerRegion,
  Set<String>? regions,
}) {
  final byRegion = <String, List<LocalPhoto>>{};
  for (final photo in photos) {
    final region = photo.regionId;
    if (region == null || (regions != null && !regions.contains(region))) {
      continue;
    }
    byRegion.putIfAbsent(region, () => []).add(photo);
  }
  final selected = <String>{};
  for (final list in byRegion.values) {
    list.sort((a, b) => a.takenAt.compareTo(b.takenAt));
    if (list.length <= perRegion || perRegion == 1) {
      selected.addAll(list.take(perRegion).map((p) => p.assetId));
      continue;
    }
    // 첫 장과 마지막 장을 포함해 같은 간격으로 고른다
    for (var i = 0; i < perRegion; i++) {
      selected.add(
        list[(i * (list.length - 1) / (perRegion - 1)).round()].assetId,
      );
    }
  }
  return selected;
}
