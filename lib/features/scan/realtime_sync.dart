import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../album/album_providers.dart';
import '../auth/auth_state.dart';
import 'scan_providers.dart';

// 알림은 행 정보를 담지 않는다. 구독 준비·재연결·앱 복귀 때 조회로 빠진 변경을 메운다.
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

  void subscribe(RealtimeChannel channel, void Function() refresh) {
    channel.subscribe((status, [_]) {
      if (isCurrent() && status == RealtimeSubscribeStatus.subscribed) {
        refresh();
      }
    });
  }

  final userChannel = client.channel(
    'user:$userId',
    opts: const RealtimeChannelConfig(private: true),
  )..onBroadcast(event: 'membership', callback: (_) => refreshMembership());
  subscribe(userChannel, refreshMembership);

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
              ref.invalidate(matchedDaysProvider);
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
      ref.invalidate(scanSnapshotProvider);
      refreshAll();
    },
  );
  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(client.removeChannel(userChannel));
    if (coupleChannel != null) unawaited(client.removeChannel(coupleChannel!));
    if (sharesChannel != null) unawaited(client.removeChannel(sharesChannel!));
  });
});
