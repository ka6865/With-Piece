import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../features/scan/photo_days.dart';

// 승인 범위만 서버에 저장한다. 원본 photo_days는 상대에게 공개하지 않는다.
class PhotoSharingRepository {
  const PhotoSharingRepository(this._client);
  final SupabaseClient _client;

  Future<Result<Set<PhotoDay>>> approved(String coupleId) => guard(() async {
    final days = <PhotoDay>{};
    for (var offset = 0; ; offset += 1000) {
      final rows = await _client
          .from('photo_day_shares')
          .select('day, region_id')
          .eq('couple_id', coupleId)
          .order('day')
          .order('region_id')
          .range(offset, offset + 999);
      days.addAll(
        rows.map(
          (row) => PhotoDay(
            DateTime.parse(row['day'] as String),
            row['region_id'] as String,
          ),
        ),
      );
      if (rows.length < 1000) return days;
    }
  });

  Future<Result<void>> replace(String coupleId, Set<PhotoDay> days) =>
      guard(() async {
        await _client.rpc(
          'replace_photo_day_shares',
          params: {
            'p_couple_id': coupleId,
            'p_rows': [
              for (final day in days)
                {
                  'day': day.day.toIso8601String().substring(0, 10),
                  'region_id': day.regionId,
                },
            ],
          },
        );
      });
}
