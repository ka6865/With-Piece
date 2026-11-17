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
    final me = _client.auth.currentUser!.id;
    final couples = await _client
        .from('couples')
        .select('user_a_id, user_b_id')
        .eq('status', 'archived');
    final partners = [
      for (final c in couples)
        (c['user_a_id'] == me ? c['user_b_id'] : c['user_a_id']) as String,
    ];
    if (partners.isEmpty) return const <DateTime>[];
    final rows = await _client
        .from('users')
        .select('deletion_requested_at')
        .inFilter('id', partners)
        .not('deletion_requested_at', 'is', null);
    return [
      for (final row in rows)
        _deletionDate(row['deletion_requested_at'] as String?)!,
    ];
  });

  static DateTime? _deletionDate(String? requestedAt) => requestedAt == null
      ? null
      : DateTime.parse(requestedAt).toLocal().add(grace);
}
