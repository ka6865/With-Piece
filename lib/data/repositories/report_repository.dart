import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';

class ReportRepository {
  const ReportRepository(this._client);

  final SupabaseClient _client;

  Future<Result<void>> submit({
    required String kind,
    required String targetId,
    required String reason,
  }) => guard(() async {
    await _client.rpc(
      'submit_content_report',
      params: {'p_kind': kind, 'p_target_id': targetId, 'p_reason': reason},
    );
  });
}
