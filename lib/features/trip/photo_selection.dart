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
