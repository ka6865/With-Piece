import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';

// 조각 대표 사진과 구도(조각채우기·최신화·대표사진 설계 4.3). 구도는 조각 bbox 기준
// 정규화 값이라 화면 크기나 투영이 바뀌어도 같은 영역이 보인다
class RegionCover {
  const RegionCover({
    required this.regionId,
    required this.photoId,
    this.scale = 1,
    this.centerX = 0.5,
    this.centerY = 0.5,
  });

  final String regionId;
  final String photoId;
  // 조각 bbox를 덮는 최소 배율 대비 배수(1 이상)
  final double scale;
  // 조각 bbox 중심에 오는 사진 위 점(너비·높이 대비 0~1)
  final double centerX;
  final double centerY;
}

class RegionCoverRepository {
  const RegionCoverRepository(this._client);

  final SupabaseClient _client;

  Future<Result<Map<String, RegionCover>>> covers(String coupleId) =>
      guard(() async {
        final rows = await _client
            .from('region_covers')
            .select('region_id, photo_id, scale, center_x, center_y')
            .eq('couple_id', coupleId);
        return {
          for (final row in rows)
            row['region_id'] as String: RegionCover(
              regionId: row['region_id'] as String,
              photoId: row['photo_id'] as String,
              scale: (row['scale'] as num).toDouble(),
              centerX: (row['center_x'] as num).toDouble(),
              centerY: (row['center_y'] as num).toDouble(),
            ),
        };
      });

  // 두 사람 누구나 바꾸고 나중 것이 남는다
  Future<Result<void>> save(String coupleId, RegionCover cover) => guard(
    () => _client.from('region_covers').upsert({
      'couple_id': coupleId,
      'region_id': cover.regionId,
      'photo_id': cover.photoId,
      'scale': cover.scale,
      'center_x': cover.centerX,
      'center_y': cover.centerY,
    }),
  );
}
