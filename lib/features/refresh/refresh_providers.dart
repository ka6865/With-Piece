import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/refresh_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../auth/auth_state.dart';
import '../scan/trip_candidates.dart';

// 현재 커플 두 사람의 최신화 상태(사용자 id별). Realtime 'refresh' 알림으로 다시 읽는다
final refreshStatesProvider = FutureProvider<Map<String, RefreshState>>((
  ref,
) async {
  ref.watch(sessionUserIdProvider);
  final couple = await ref.watch(currentCoupleProvider.future);
  if (couple == null) return const {};
  return (await ref.watch(refreshRepositoryProvider).states(couple.id))
      .valueOrThrow;
});

// 내가 받은, 아직 처리하지 않은 요청. 하단 탭 점과 홈 카드가 쓴다
final receivedRefreshRequestProvider = Provider<RefreshState?>((ref) {
  final userId = ref.watch(sessionUserIdProvider);
  final mine = ref.watch(refreshStatesProvider).value?[userId];
  return mine?.requestedAt == null ? null : mine;
});

const refreshRequestCooldown = Duration(hours: 1);

// 이름이 없으면 '상대'로 쓴다. 조사가 달라 주어·소유 형태를 따로 만든다
String partnerTopic(String? name) => name == null ? '상대는' : '$name님은';
String partnerOf(String? name) => name == null ? '상대의' : '$name님의';
String partnerSubject(String? name) => name == null ? '상대가' : '$name님이';
String partnerTo(String? name) => name == null ? '상대에게' : '$name님에게';

String daysAgo(DateTime time, DateTime now) {
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(time.year, time.month, time.day)).inDays;
  return switch (days) {
    <= 0 => '오늘',
    1 => '어제',
    _ => '$days일 전에',
  };
}

// 업데이트 전에 저장한 기록은 시각이 없어 "안 했다"고 단정하지 않는다(설계 4.2)
String partnerRefreshText(String? name, DateTime? refreshedAt, DateTime now) =>
    refreshedAt == null
    ? '${partnerOf(name)} 최신화 기록이 아직 없어요'
    : '${partnerTopic(name)} ${daysAgo(refreshedAt, now)} 마지막으로 최신화했어요';

bool canRequestRefresh(RefreshState? partner, String myId, DateTime now) {
  final at =
      partner?.lastRequestedAt ??
      (partner?.requestedBy == myId ? partner?.requestedAt : null);
  return at == null || now.difference(at) >= refreshRequestCooldown;
}

// 저장 전 후보에 없던 기간의 후보 수. 저장 전 후보를 모르면 null
int? newCandidateCount(List<TripCandidate>? before, List<TripCandidate> after) {
  if (before == null) return null;
  final known = {for (final c in before) c.range};
  return after.where((c) => !known.contains(c.range)).length;
}

String sharingSavedMessage(int? found) => switch (found) {
  null => '비교할 기록을 저장했어요',
  0 => '새로 찾은 여행이 없어요',
  _ => '새 여행 $found개를 찾았어요',
};
