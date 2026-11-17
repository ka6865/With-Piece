import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../album/album_providers.dart';
import '../auth/auth_state.dart';
import 'photo_sharing_page.dart';
import 'scan_providers.dart';

// 알림은 행 정보를 담지 않는다. 재연결·앱 복귀 때 조회로 빠진 변경을 메운다.
// 첫 가입은 방금 읽은 값을 다시 읽지 않도록 건너뛴다.
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

  void refreshTrips() {
    ref
      ..invalidate(tripsProvider)
      ..invalidate(archivedTripsProvider);
  }

  void refreshPhotos() {
    ref
      ..invalidate(couplePhotosProvider)
      ..invalidate(archivedPhotosProvider);
  }

  void refreshCouple() {
    if (!isCurrent()) return;
    refreshTrips();
    refreshPhotos();
    ref
      ..invalidate(overridesProvider)
      ..invalidate(currentCoupleProvider)
      ..invalidate(archivedCouplesProvider);
  }

  void refreshAll() {
    if (!isCurrent()) return;
    refreshCouple();
    ref.invalidate(matchedDaysProvider);
  }

  void refreshMembership() {
    if (!isCurrent()) return;
    ref
      ..invalidate(currentCoupleProvider)
      ..invalidate(archivedCouplesProvider);
  }

  void subscribe(
    RealtimeChannel channel,
    void Function() refresh, {
    void Function(bool joined)? onStatus,
  }) {
    var joinedOnce = false;
    channel.subscribe((status, [_]) {
      if (!isCurrent()) return;
      final joined = status == RealtimeSubscribeStatus.subscribed;
      onStatus?.call(joined);
      if (!joined) return;
      if (joinedOnce) refresh();
      joinedOnce = true;
    });
  }

  // 연결 대기 중 사용자 채널이 붙지 않으면 상대 수락 알림을 못 받으므로 조회로 대신한다
  Timer? fallback;
  void onUserChannel(bool joined) {
    fallback?.cancel();
    fallback = joined
        ? null
        : Timer.periodic(const Duration(seconds: 15), (_) {
            if (coupleId == null) refreshMembership();
          });
  }

  final userChannel = client.channel(
    'user:$userId',
    opts: const RealtimeChannelConfig(private: true),
  )..onBroadcast(event: 'membership', callback: (_) => refreshMembership());
  subscribe(userChannel, refreshMembership, onStatus: onUserChannel);

  // 재조회 중에는 기존 구독을 유지하고, 확인된 ID가 달라졌을 때만 교체한다.
  ref.listen(currentCoupleProvider, (_, next) {
    if (!isCurrent() || next.isLoading || next.hasError) return;
    final nextId = next.value?.id;
    if (nextId == coupleId) return;
    coupleId = nextId;
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
    on('trips', refreshTrips);
    on('overrides', () => ref.invalidate(overridesProvider));
    on('photos', refreshPhotos);
    on('couple', () {
      ref
        ..invalidate(currentCoupleProvider)
        ..invalidate(archivedCouplesProvider);
    });
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
            if (isCurrent() && coupleId == nextId) {
              ref
                ..invalidate(matchedDaysProvider)
                ..invalidate(photoSharingChoicesProvider);
            }
          },
        );
    sharesChannel = shares;
    subscribe(shares, () {
      if (coupleId == nextId) ref.invalidate(matchedDaysProvider);
    });
  }, fireImmediately: true);

  final lifecycle = AppLifecycleListener(
    onResume: () {
      if (!isCurrent()) return;
      // 사진첩 재스캔은 비교에 쓰는 커플만 한다. 혼자일 때는 화면을 열 때 스캔한다
      if (coupleId != null) ref.invalidate(scanSnapshotProvider);
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
