import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';

// 계정 삭제 30일 유예(설계 14.1)
class AccountRepository {
  const AccountRepository(this._client);

  static const grace = Duration(days: 30);

  final SupabaseClient _client;

  Future<Result<void>> requestDeletion() =>
      guard(() => _client.rpc('request_account_deletion'));

  Future<Result<void>> cancelDeletion() =>
      guard(() => _client.rpc('cancel_account_deletion'));

  // 계정이 지워지는 날. 요청이 없으면 null
  Future<Result<DateTime?>> myDeletionDate() => guard(() async {
    final row = await _client
        .from('users')
        .select('deletion_requested_at')
        .eq('id', _client.auth.currentUser!.id)
        .single();
    return _deletionDate(row['deletion_requested_at'] as String?);
  });

  // 아카이브된 커플의 상대가 삭제를 요청했으면 함께한 기록이 사라지는 날
  Future<Result<List<DateTime>>> partnerDeletionDates() => guard(() async {
    final rows = await _client.rpc('archived_couples') as List;
    return {
      for (final row in rows.cast<Map<String, dynamic>>())
        if (row['partner_deletion_requested_at'] case final String requested)
          _deletionDate(requested)!,
    }.toList();
  });

  static DateTime? _deletionDate(String? requestedAt) => requestedAt == null
      ? null
      : DateTime.parse(requestedAt).toLocal().add(grace);
}
