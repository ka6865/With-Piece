import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/repository_providers.dart';
import '../album/album_providers.dart';
import '../album/comments.dart';
import '../auth/account_state.dart';
import '../auth/auth_state.dart';
import '../map/region_covers.dart';
import '../refresh/refresh_providers.dart';
import 'photo_sharing_page.dart';
import 'scan_providers.dart';

// 알림은 행 정보를 담지 않는다. 가입·재연결·앱 복귀 때 조회로 빠진 변경을 메운다.
// 첫 가입도 다시 읽는다. 첫 조회와 가입 사이의 변경(초대 수락 등)은 알림으로 오지 않는다.
final realtimeSyncProvider = Provider<void>((ref) {
  final userId = ref.watch(sessionUserIdProvider);
  if (userId == null) return;
  final client = ref.watch(supabaseClientProvider);
  String? coupleId;
  RealtimeChannel? coupleChannel;
  RealtimeChannel? sharesChannel;

  bool isCurrent() =>
      ref.mounted &&
      client.auth.currentUser?.id == userId &&
      ref.read(sessionUserIdProvider) == userId;

  void refreshArchive() {
    if (!isCurrent()) return;
    ref
      ..invalidate(myDeletionDateProvider(userId))
      ..invalidate(partnerDeletionDatesProvider(userId))
      ..invalidate(archivedCouplesProvider)
      ..invalidate(archivedTripsProvider)
      ..invalidate(archivedPhotosProvider);
  }

  void refreshComments() {
    ref
      ..invalidate(commentsProvider)
      ..invalidate(partnerCommentTimesProvider);
  }

  void refreshCouple() {
    if (!isCurrent()) return;
    refreshComments();
    ref
      ..invalidate(tripsProvider)
      ..invalidate(couplePhotosProvider)
      ..invalidate(overridesProvider)
      ..invalidate(refreshStatesProvider)
      ..invalidate(regionCoversProvider)
      ..invalidate(currentCoupleProvider);
  }

  void refreshAll() {
    if (!isCurrent()) return;
    refreshCouple();
    refreshArchive();
    ref.invalidate(matchedDaysProvider);
  }

  void refreshShares() {
    if (!isCurrent()) return;
    ref
      ..invalidate(matchedDaysProvider)
      ..invalidate(photoSharingChoicesProvider);
  }

  void refreshMembership() {
    if (!isCurrent()) return;
    ref.invalidate(currentCoupleProvider);
    refreshArchive();
  }

  void subscribe(
    RealtimeChannel channel,
    void Function() refresh, {
    void Function(bool joined)? onStatus,
  }) {
    channel.subscribe((status, [_]) {
      if (!isCurrent()) return;
      final joined = status == RealtimeSubscribeStatus.subscribed;
      onStatus?.call(joined);
      if (joined) refresh();
    });
  }

  // 구독이 붙어도 합류 신호가 누락될 수 있다. 유효한 초대가 있는 동안 관계만 다시 읽는다.
  Timer? fallback;
  var userChannelJoined = false;
  void updateFallback() {
    if (coupleId != null) {
      fallback?.cancel();
      fallback = null;
      return;
    }
    fallback ??= Timer.periodic(const Duration(seconds: 15), (_) {
      if (!isCurrent() ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final inviteProvider = myInviteProvider(userId);
      final invite = ref.exists(inviteProvider)
          ? ref.read(inviteProvider).value
          : null;
      if (!userChannelJoined ||
          (invite?.expiresAt.isAfter(DateTime.now()) ?? false)) {
        ref.invalidate(currentCoupleProvider);
      }
    });
  }

  final userChannel =
      client.channel(
          'user:$userId',
          opts: const RealtimeChannelConfig(private: true),
        )
        ..onBroadcast(event: 'membership', callback: (_) => refreshMembership())
        ..onBroadcast(event: 'archive', callback: (_) => refreshArchive());
  subscribe(
    userChannel,
    refreshMembership,
    onStatus: (joined) {
      userChannelJoined = joined;
      updateFallback();
    },
  );
  updateFallback();

  // 재조회 중에는 기존 구독을 유지하고, 확인된 ID가 달라졌을 때만 교체한다.
  ref.listen(currentCoupleProvider, (_, next) {
    if (!isCurrent() || next.isLoading || next.hasError) return;
    final nextId = next.value?.id;
    if (nextId == coupleId) return;
    coupleId = nextId;
    updateFallback();
    if (coupleChannel != null) unawaited(client.removeChannel(coupleChannel!));
    if (sharesChannel != null) unawaited(client.removeChannel(sharesChannel!));
    coupleChannel = null;
    sharesChannel = null;
    if (nextId == null) return;

    final channel = client.channel(
      'couple:$nextId',
      opts: const RealtimeChannelConfig(private: true),
    );
    coupleChannel = channel;
    void on(String event, void Function() refresh) => channel.onBroadcast(
      event: event,
      callback: (_) {
        if (isCurrent() && coupleId == nextId) refresh();
      },
    );
    on('trips', () => ref.invalidate(tripsProvider));
    on('overrides', () => ref.invalidate(overridesProvider));
    on('photos', () => ref.invalidate(couplePhotosProvider));
    on('comments', refreshComments);
    on('refresh', () => ref.invalidate(refreshStatesProvider));
    on('covers', () => ref.invalidate(regionCoversProvider));
    on('couple', refreshMembership);
    subscribe(channel, () {
      if (coupleId == nextId) refreshCouple();
    });
    final shares =
        client.channel(
          'couple-shares:$nextId',
          opts: const RealtimeChannelConfig(private: true),
        )..onBroadcast(
          event: 'shares',
          callback: (_) {
            if (coupleId == nextId) refreshShares();
          },
        );
    sharesChannel = shares;
    subscribe(shares, () {
      if (coupleId == nextId) refreshShares();
    });
  }, fireImmediately: true);

  final lifecycle = AppLifecycleListener(
    onResume: () {
      if (!isCurrent()) return;
      if (coupleId != null) {
        ref.invalidate(scanSnapshotProvider(userId));
      } else if (ref.exists(scanSnapshotProvider(userId)) &&
          ref.read(scanSnapshotProvider(userId)).hasError) {
        // 혼자일 때는 이미 실패한 스캔만, 설정에서 전체 접근을 허용하고 돌아왔을 때
        // 다시 한다. 권한 창을 다시 띄우지 않도록 상태만 확인한다
        unawaited(
          ref
              .read(photoLibraryRepositoryProvider)
              .hasFullAccess()
              .then((ok) {
                if (ok && isCurrent()) {
                  ref.invalidate(scanSnapshotProvider(userId));
                }
              })
              // 확인에 실패하면 스캔 오류를 그대로 두고 다음 복귀에서 다시 확인한다
              .catchError((Object _) {}),
        );
      }
      refreshAll();
    },
  );
  ref.onDispose(() {
    lifecycle.dispose();
    fallback?.cancel();
    unawaited(client.removeChannel(userChannel));
    if (coupleChannel != null) unawaited(client.removeChannel(coupleChannel!));
    if (sharesChannel != null) unawaited(client.removeChannel(sharesChannel!));
  });
});
