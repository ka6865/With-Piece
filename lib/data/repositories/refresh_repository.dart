import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';

// 한 사람의 여행 최신화 상태. 날짜·지역 내용은 담지 않는다(조각채우기·최신화·대표사진 설계 4.2)
class RefreshState {
  const RefreshState({
    this.refreshedAt,
    this.requestedAt,
    this.requestedBy,
    this.lastRequestedAt,
  });

  // 비교할 기록 선택을 마지막으로 저장한 시각. 업데이트 전 저장은 남아 있지 않다
  final DateTime? refreshedAt;
  // 이 사람이 받은, 아직 처리하지 않은 요청
  final DateTime? requestedAt;
  final String? requestedBy;
  final DateTime? lastRequestedAt;
}

class RefreshRepository {
  const RefreshRepository(this._client);

  final SupabaseClient _client;

  // 사용자 id별 상태. 행이 없는 사람은 빠진다
  Future<Result<Map<String, RefreshState>>> states(
    String coupleId,
  ) => guard(() async {
    final rows = await _client
        .from('couple_refresh_state')
        .select(
          'user_id, refreshed_at, requested_at, requested_by, last_requested_at',
        )
        .eq('couple_id', coupleId);
    DateTime? time(Object? value) =>
        value == null ? null : DateTime.parse(value as String).toLocal();
    return {
      for (final row in rows)
        row['user_id'] as String: RefreshState(
          refreshedAt: time(row['refreshed_at']),
          requestedAt: time(row['requested_at']),
          requestedBy: row['requested_by'] as String?,
          lastRequestedAt: time(row['last_requested_at']),
        ),
    };
  });

  // 1시간 안에 다시 보내면 서버가 거부한다(AppError.validation)
  Future<Result<void>> request() => guard(() => _client.rpc('request_refresh'));

  Future<Result<void>> markRefreshed() =>
      guard(() => _client.rpc('mark_refreshed'));
}
