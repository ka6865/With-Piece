import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';
import '../album/album_providers.dart';
import '../auth/auth_state.dart';
import 'scan_providers.dart';

// 상대의 변경을 받아 관련 provider를 다시 읽는다. Realtime은 편의 기능이고 정합성의
// 근거가 아니므로 재연결과 앱 복귀 때 전체를 다시 읽는다(설계 12장)
final realtimeSyncProvider = Provider<void>((ref) {
  final userId = ref.watch(sessionUserIdProvider);
  final coupleId = ref.watch(currentCoupleProvider).value?.id;
  if (coupleId == null) {
    if (userId == null) return;
    final timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (ref.mounted) {
        ref.invalidate(currentCoupleProvider);
      } else {
        timer.cancel();
      }
    });
    final lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(currentCoupleProvider),
    );
    ref.onDispose(() {
      timer.cancel();
      lifecycle.dispose();
    });
    return;
  }
  final client = ref.watch(supabaseClientProvider);

  void refreshAll() {
    if (!ref.mounted) return;
    ref
      ..invalidate(tripsProvider)
      ..invalidate(overridesProvider)
      ..invalidate(currentCoupleProvider)
      ..invalidate(matchedDaysProvider)
      ..invalidate(couplePhotosProvider)
      ..invalidate(archivedCouplesProvider)
      ..invalidate(archivedTripsProvider)
      ..invalidate(archivedPhotosProvider);
  }

  final channel = client.channel('couple:$coupleId');
  void on(String table, String column, void Function() refresh) =>
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: column,
          value: coupleId,
        ),
        callback: (_) {
          if (ref.mounted) refresh();
        },
      );
  on('trips', 'couple_id', () => ref.invalidate(tripsProvider));
  on('trip_regions', 'couple_id', () => ref.invalidate(tripsProvider));
  on(
    'couple_region_overrides',
    'couple_id',
    () => ref.invalidate(overridesProvider),
  );
  on('photos', 'couple_id', () {
    ref
      ..invalidate(couplePhotosProvider)
      ..invalidate(archivedPhotosProvider);
  });
  // 사귄 날이 바뀌면 currentCoupleProvider를 거쳐 photo_days가 다시 맞춰진다(설계 5.2)
  on('couples', 'id', () => ref.invalidate(currentCoupleProvider));
  var subscribedOnce = false;
  channel.subscribe((status, [_]) {
    if (!ref.mounted || status != RealtimeSubscribeStatus.subscribed) return;
    // 첫 구독은 이미 최신이다. 이후의 구독은 재연결이므로 놓친 변경을 메운다
    if (subscribedOnce) refreshAll();
    subscribedOnce = true;
  });

  // 상대의 photo_days 변경은 RLS로 받을 수 없으므로 앱 복귀 때 스캔부터 다시 한다
  final lifecycle = AppLifecycleListener(
    onResume: () {
      if (!ref.mounted) return;
      ref.invalidate(scanSnapshotProvider);
      refreshAll();
    },
  );
  ref.onDispose(() {
    lifecycle.dispose();
    client.removeChannel(channel);
  });
});
