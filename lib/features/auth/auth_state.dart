import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/couple_repository.dart';
import '../../data/repositories/repository_providers.dart';

// 라우터가 화면을 고르는 기준. unavailable(오프라인 등)에서는 이동하지 않아
// 번들 지도가 계속 보이게 한다(설계 12장)
enum AppStage {
  loading,
  signedOut,
  needsCouple,
  needsStartedOn,
  ready,
  unavailable,
}

final currentCoupleProvider = FutureProvider<Couple?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session.isLoading || session.hasError || session.value == null) {
    return null;
  }
  return (await ref.watch(coupleRepositoryProvider).current()).valueOrThrow;
});

final appStageProvider = Provider<AppStage>(
  (ref) => switch (ref.watch(sessionProvider)) {
    AsyncData(value: null) => AppStage.signedOut,
    AsyncData() => switch (ref.watch(currentCoupleProvider)) {
      AsyncData(value: null) => AppStage.needsCouple,
      AsyncData(value: Couple(startedOn: null)) => AppStage.needsStartedOn,
      AsyncData() => AppStage.ready,
      AsyncError() => AppStage.unavailable,
      _ => AppStage.loading,
    },
    AsyncError() => AppStage.unavailable,
    _ => AppStage.loading,
  },
);

// 로그인 전에 초대 딥링크로 받은 코드. 로그인 뒤 초대 화면이 꺼내 쓴다(설계 10.3)
class PendingInviteCode extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? code) => state = code;
}

final pendingInviteCodeProvider = NotifierProvider<PendingInviteCode, String?>(
  PendingInviteCode.new,
);

final myInviteProvider = FutureProvider.family<Invite?, String>((
  ref,
  userId,
) async {
  if (ref.watch(sessionUserIdProvider) != userId) return null;
  return (await ref.watch(coupleRepositoryProvider).myInvite()).valueOrThrow;
});

final identitiesProvider = FutureProvider.family<List<UserIdentity>, String>((
  ref,
  userId,
) async {
  if (ref.watch(sessionUserIdProvider) != userId) return const [];
  return (await ref.watch(authRepositoryProvider).identities()).valueOrThrow;
});
