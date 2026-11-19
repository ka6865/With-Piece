import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';

class Invite {
  const Invite({required this.code, required this.expiresAt});

  final String code;
  final DateTime expiresAt;
}

class Couple {
  const Couple({
    required this.id,
    required this.partnerId,
    this.startedOn,
    this.myName,
    this.partnerName,
    this.myHomeRegionId,
  });

  final String id;
  final String partnerId;
  final DateTime? startedOn;
  // 홈의 이니셜 표시용 닉네임. 로그인 제공자가 이름을 주지 않으면 없다
  final String? myName;
  final String? partnerName;
  // 내가 고른 사는 곳(users.home_region_id). 비교할 기록 목록에서 접는다
  final String? myHomeRegionId;
}

// 아카이브된 커플. 기록은 읽기 전용으로 남는다(설계 14장)
class ArchivedCouple {
  const ArchivedCouple({
    required this.id,
    required this.partnerName,
    required this.archivedAt,
    this.partnerDeletionDate,
  });

  final String id;
  final String partnerName;
  final DateTime archivedAt;
  // 상대가 계정 삭제를 요청했으면 함께한 기록이 사라지는 날(설계 14.1)
  final DateTime? partnerDeletionDate;
}

enum JoinOutcome {
  joined,
  invalidCode,
  expired,
  self,
  alreadyCoupled,
  rateLimited,
  deletionPending,
}

// 커플 관계는 RPC로만 바뀐다(설계 9.3). 테이블에는 읽기만 한다
class CoupleRepository {
  const CoupleRepository(this._client);

  final SupabaseClient _client;

  static const _outcomes = {
    'ok': JoinOutcome.joined,
    'invalid_code': JoinOutcome.invalidCode,
    'expired': JoinOutcome.expired,
    'self': JoinOutcome.self,
    'already_coupled': JoinOutcome.alreadyCoupled,
    'rate_limited': JoinOutcome.rateLimited,
    'deletion_pending': JoinOutcome.deletionPending,
  };

  Future<Result<Invite>> createInvite() => guard(() async {
    final rows = await _client.rpc('create_invite') as List;
    return _inviteOf(rows.single as Map<String, dynamic>);
  });

  Future<Result<Invite?>> myInvite() => guard(() async {
    final rows = await _client.rpc('my_invite') as List;
    return rows.isEmpty ? null : _inviteOf(rows.single as Map<String, dynamic>);
  });

  Future<Result<JoinOutcome>> join(String code) async {
    final result = await guard(
      () async =>
          await _client.rpc('join_couple', params: {'p_code': code}) as String,
    );
    return switch (result) {
      Ok(:final value) when _outcomes.containsKey(value) => Ok(
        _outcomes[value]!,
      ),
      Ok() => const Err(AppError.unknown),
      Err(:final error) => Err(error),
    };
  }

  // 개발 전용. 서버 함수는 개발 프로젝트에만 있다(lib/core/dev_flags.dart)
  Future<Result<JoinOutcome>> joinDevSolo() async {
    final result = await guard(
      () async => await _client.rpc('dev_solo_join') as String,
    );
    return switch (result) {
      Ok(:final value) when _outcomes.containsKey(value) => Ok(
        _outcomes[value]!,
      ),
      Ok() => const Err(AppError.unknown),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> setStartedOn(DateTime date) => guard(
    () => _client.rpc(
      'set_started_on',
      params: {'p_date': date.toIso8601String().substring(0, 10)},
    ),
  );

  // 사는 곳은 사람에 속한다(설계 6.2 거주지). 본인 행만 고칠 수 있다
  Future<Result<void>> setHomeRegion(String regionId) => guard(
    () => _client
        .from('users')
        .update({'home_region_id': regionId})
        .eq('id', _client.auth.currentUser!.id),
  );

  Future<Result<void>> archive() => guard(() => _client.rpc('archive_couple'));

  Future<Result<Couple?>> current() => guard(() async {
    final me = _client.auth.currentUser!.id;
    // 사용자와 활성 커플을 한 요청으로 읽는다. 앱 시작·Realtime 가입마다 불린다
    final user = await _client
        .from('users')
        .select(
          'nickname, home_region_id, couple:couples!users_active_couple_fk(id, user_a_id, user_b_id, started_on, '
          'a:users!couples_user_a_id_fkey(nickname), b:users!couples_user_b_id_fkey(nickname))',
        )
        .eq('id', me)
        .single();
    final row = user['couple'] as Map<String, dynamic>?;
    if (row == null) return null;
    final startedOn = row['started_on'] as String?;
    final iAmA = row['user_a_id'] == me;
    final partner = (iAmA ? row['b'] : row['a']) as Map<String, dynamic>?;
    return Couple(
      id: row['id'] as String,
      partnerId: (iAmA ? row['user_b_id'] : row['user_a_id']) as String,
      startedOn: startedOn == null ? null : DateTime.parse(startedOn),
      myName: user['nickname'] as String?,
      partnerName: partner?['nickname'] as String?,
      myHomeRegionId: user['home_region_id'] as String?,
    );
  });

  static Invite _inviteOf(Map<String, dynamic> row) => Invite(
    code: row['code'] as String,
    expiresAt: DateTime.parse(row['expires_at'] as String),
  );

  Future<Result<List<ArchivedCouple>>> archived() => guard(() async {
    final me = _client.auth.currentUser!.id;
    final couples = await _client
        .from('couples')
        .select('id, user_a_id, user_b_id, archived_at')
        .eq('status', 'archived')
        .order('archived_at', ascending: false);
    if (couples.isEmpty) return const <ArchivedCouple>[];
    String partnerOf(Map<String, dynamic> c) =>
        (c['user_a_id'] == me ? c['user_b_id'] : c['user_a_id']) as String;
    final users = {
      for (final u
          in await _client
              .from('users')
              .select('id, nickname, deletion_requested_at')
              .inFilter('id', [for (final c in couples) partnerOf(c)]))
        u['id'] as String: u,
    };
    return [
      for (final c in couples)
        ArchivedCouple(
          id: c['id'] as String,
          partnerName: users[partnerOf(c)]?['nickname'] as String? ?? '지난 연인',
          archivedAt: DateTime.parse(c['archived_at'] as String).toLocal(),
          partnerDeletionDate: switch (users[partnerOf(
            c,
          )]?['deletion_requested_at']) {
            final String requested => DateTime.parse(
              requested,
            ).toLocal().add(const Duration(days: 30)),
            _ => null,
          },
        ),
    ];
  });
}
