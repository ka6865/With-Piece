import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../features/scan/photo_days.dart';

// 서버로 가는 위치 정보는 (날짜, 조각, 장수)뿐이다(설계 5.2)
class PhotoDayRepository {
  const PhotoDayRepository(this._client);

  final SupabaseClient _client;

  Future<Result<void>> replaceAll(Map<PhotoDay, int> days) => guard(
    () => _client.rpc(
      'replace_photo_days',
      params: {
        'p_rows': [
          for (final MapEntry(key: day, value: count) in days.entries)
            {
              'day': _date(day.day),
              'region_id': day.regionId,
              'photo_count': count,
            },
        ],
      },
    ),
  );

  Future<Result<void>> sync(String coupleId, Map<PhotoDay, int> days) => guard(
    () => _client.rpc(
      'sync_photo_days',
      params: {
        'p_couple_id': coupleId,
        'p_rows': [
          for (final MapEntry(key: day, value: count) in days.entries)
            {
              'day': _date(day.day),
              'region_id': day.regionId,
              'photo_count': count,
            },
        ],
      },
    ),
  );

  Future<Result<Map<PhotoDay, int>>> mine() => guard(() async {
    final rows = await _client
        .from('photo_days')
        .select('day, region_id, photo_count');
    return {
      for (final row in rows)
        PhotoDay(
          DateTime.parse(row['day'] as String),
          row['region_id'] as String,
        ): row['photo_count'] as int,
    };
  });

  static String _date(DateTime day) => day.toIso8601String().substring(0, 10);
}
