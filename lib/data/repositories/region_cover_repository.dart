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
    this.blackBackground = false,
  });

  final String regionId;
  final String photoId;
  // 조각 bbox를 덮는 최소 배율 대비 배수(0.25~8). 1 미만이면 사진이 조각 안에 다 보인다
  final double scale;
  // 조각 bbox 중심에 오는 사진 위 점(너비·높이 대비, 축소하면 0~1을 벗어난다)
  final double centerX;
  final double centerY;
  // 축소해 생긴 빈 곳을 검은색으로 칠한다. 아니면 흰색
  final bool blackBackground;
}

class RegionCoverRepository {
  const RegionCoverRepository(this._client);

  final SupabaseClient _client;

  Future<Result<Map<String, RegionCover>>> covers(String coupleId) => guard(
    () async {
      final rows = await _client
          .from('region_covers')
          .select(
            'region_id, photo_id, scale, center_x, center_y, black_background',
          )
          .eq('couple_id', coupleId);
      return {
        for (final row in rows)
          row['region_id'] as String: RegionCover(
            regionId: row['region_id'] as String,
            photoId: row['photo_id'] as String,
            scale: (row['scale'] as num).toDouble(),
            centerX: (row['center_x'] as num).toDouble(),
            centerY: (row['center_y'] as num).toDouble(),
            blackBackground: row['black_background'] as bool,
          ),
      };
    },
  );

  // 두 사람 누구나 바꾸고 나중 것이 남는다. upsert는 충돌 시 커플·조각 칸까지
  // 고치려 해 그 칸의 수정 권한이 없어 거부된다. 고칠 행이 없을 때만 넣는다
  Future<Result<void>> save(String coupleId, RegionCover cover) =>
      guard(() async {
        final values = {
          'photo_id': cover.photoId,
          'scale': cover.scale,
          'center_x': cover.centerX,
          'center_y': cover.centerY,
          'black_background': cover.blackBackground,
        };
        Future<bool> update() async =>
            (await _client
                    .from('region_covers')
                    .update(values)
                    .eq('couple_id', coupleId)
                    .eq('region_id', cover.regionId)
                    .select('region_id'))
                .isNotEmpty;
        if (await update()) return;
        try {
          await _client.from('region_covers').insert({
            'couple_id': coupleId,
            'region_id': cover.regionId,
            ...values,
          });
        } on PostgrestException catch (error) {
          // 상대가 같은 조각을 먼저 넣었으면 그 행을 고친다
          if (error.code != '23505' || !await update()) rethrow;
        }
      });
}
