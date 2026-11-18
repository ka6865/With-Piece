import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../features/scan/photo_days.dart';
import 'fetch_all.dart';

// 승인 범위만 서버에 저장한다. 원본 photo_days는 상대에게 공개하지 않는다.
class PhotoSharingRepository {
  const PhotoSharingRepository(this._client);
  final SupabaseClient _client;

  Future<Result<Map<PhotoDay, int>>> approvedWithCounts(String coupleId) =>
      guard(() async {
        final rows = await fetchAll(
          (from, to) => _client
              .from('photo_day_shares')
              .select('day, region_id, photo_days!inner(photo_count)')
              .eq('couple_id', coupleId)
              .order('day')
              .order('region_id')
              .range(from, to),
        );
        return {
          for (final row in rows)
            _day(row): (row['photo_days'] as Map)['photo_count'] as int,
        };
      });

  // 승인은 이 기기의 장수를 함께 보내 다른 기기 동기화로 빠진 원본도 되살린다.
  Future<Result<void>> update(
    String coupleId, {
    required Map<PhotoDay, int> approve,
    required Set<PhotoDay> revoke,
  }) => guard(
    () => _client.rpc(
      'update_photo_day_shares',
      params: {
        'p_couple_id': coupleId,
        'p_approve': [
          for (final MapEntry(key: day, value: count) in approve.entries)
            {..._row(day), 'photo_count': count},
        ],
        'p_revoke': [for (final day in revoke) _row(day)],
      },
    ),
  );

  static PhotoDay _day(Map<String, dynamic> row) => PhotoDay(
    DateTime.parse(row['day'] as String),
    row['region_id'] as String,
  );
  static Map<String, Object> _row(PhotoDay day) => {
    'day': day.day.toIso8601String().substring(0, 10),
    'region_id': day.regionId,
  };
}
