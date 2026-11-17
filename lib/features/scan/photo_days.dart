import '../../map_data/geo_region_locator.dart';
import '../../map_data/map_asset.dart';

// 사진 한 장에서 쓰는 것은 촬영 시각과 위치뿐이다. 서버로는 보내지 않는다(설계 5.1)
class PhotoMeta {
  const PhotoMeta(this.takenAt, this.location);

  final DateTime takenAt;
  final GeoPoint location;
}

class PhotoDay {
  PhotoDay(DateTime takenAt, this.regionId)
    : day = DateTime(takenAt.year, takenAt.month, takenAt.day);

  // 기기 현지 시간 기준 촬영 날짜
  final DateTime day;
  final String regionId;

  @override
  bool operator ==(Object other) =>
      other is PhotoDay && other.day == day && other.regionId == regionId;

  @override
  int get hashCode => Object.hash(day, regionId);
}

// 사진을 (날짜, 조각)별 장수로 접는다. 바다·국외처럼 조각 밖 사진은 버린다
Map<PhotoDay, int> aggregatePhotoDays(
  Iterable<PhotoMeta> photos,
  GeoRegionLocator locator,
) {
  final counts = <PhotoDay, int>{};
  for (final photo in photos) {
    final regionId = locator.regionAt(photo.location);
    if (regionId == null) continue;
    final key = PhotoDay(photo.takenAt, regionId);
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}
