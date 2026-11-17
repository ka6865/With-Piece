// 실제 가입 완료와 채널 재사용을 확인하는 테스트에서만 SDK 내부 상태를 읽는다.
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_day_repository.dart';
import 'package:woori_piece/data/repositories/photo_sharing_repository.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/album/album_providers.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/realtime_sync.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';

import 'support.dart';

Future<void> _until(FutureOr<bool> Function() ready, String reason) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail(reason);
}

// Broadcast는 PostgreSQL 복제 준비 이벤트 대신 실제 private 채널 가입 응답을 기다린다.
Future<RealtimeChannel> _joined(SupabaseClient client, String topic) async {
  await _until(
    () => client.getChannels().any(
      (c) => c.topic == 'realtime:$topic' && c.isJoined,
    ),
    '$topic 비공개 구독이 준비되지 않았어요',
  );
  return client.getChannels().singleWhere((c) => c.topic == 'realtime:$topic');
}

Future<RealtimeChannel> _listen(
  SupabaseClient client,
  String topic,
  void Function(Map<String, dynamic>) receive, {
  bool private = true,
}) async {
  final ready = Completer<void>();
  final channel = client.channel(
    topic,
    opts: RealtimeChannelConfig(private: private),
  )..onBroadcast(event: '*', callback: receive);
  channel.subscribe((status, [error]) {
    if (ready.isCompleted) return;
    if (status == RealtimeSubscribeStatus.subscribed) ready.complete();
    if (status == RealtimeSubscribeStatus.channelError) {
      ready.completeError(error!);
    }
  });
  addTearDown(() => client.removeChannel(channel));
  try {
    await ready.future.timeout(const Duration(seconds: 10));
    return channel;
  } catch (_) {
    await client.removeChannel(channel);
    rethrow;
  }
}

Future<String> _couple(SupabaseClient a, SupabaseClient b) async {
  final invite = (await CoupleRepository(a).createInvite()).valueOrThrow;
  expect(
    (await CoupleRepository(b).join(invite.code)).valueOrThrow,
    JoinOutcome.joined,
  );
  final couple = (await CoupleRepository(a).current()).valueOrThrow!;
  (await CoupleRepository(a).setStartedOn(DateTime(2026, 1, 1))).valueOrThrow;
  return couple.id;
}

Future<String> _trip(SupabaseClient a) async =>
    (await TripRepository(a).confirm(
      title: '속초시',
      range: DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 3)),
      regionIds: ['32060'],
      source: TripSource.manual,
    )).valueOrThrow;

// 실제 private 채널의 콜백에 지연된 이벤트를 넣어 계정 경계를 검증한다.
void _deliver(RealtimeChannel channel, String event) => channel.trigger(
  'broadcast',
  {'event': event, 'payload': <String, dynamic>{}},
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final skip = await localStackSkipReason();

  test('연결 대기는 private 사용자 알림으로 갱신하며 같은 커플 조회는 채널을 유지한다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(a)],
    );
    addTearDown(() async {
      container.dispose();
      await a.dispose();
      await b.dispose();
    });
    final sync = container.listen(realtimeSyncProvider, (_, _) {});
    addTearDown(sync.close);
    expect(await container.read(currentCoupleProvider.future), isNull);
    await _joined(a, 'user:${a.auth.currentUser!.id}');
    final id = await _couple(a, b);
    await _until(
      () async =>
          (await container.read(currentCoupleProvider.future))?.id == id,
      '상대 합류를 읽지 못했어요',
    );
    final channel = await _joined(a, 'couple:$id');
    await _joined(a, 'couple-shares:$id');
    container.invalidate(currentCoupleProvider);
    await container.read(currentCoupleProvider.future);
    await container.pump();
    expect(
      a.getChannels().singleWhere((c) => c.topic == 'realtime:couple:$id'),
      same(channel),
    );
    (await CoupleRepository(b).setStartedOn(DateTime(2026, 2, 1))).valueOrThrow;
    await _until(
      () async =>
          (await container.read(currentCoupleProvider.future))?.startedOn ==
          DateTime(2026, 2, 1),
      '상대의 사귄 날 변경을 읽지 못했어요',
    );
    expect(
      a.getChannels().singleWhere((c) => c.topic == 'realtime:couple:$id'),
      same(channel),
    );
  }, skip: skip);

  test('실제 앱 provider가 승인·FK 연쇄 삭제·사진 추가와 삭제를 다시 읽는다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    final id = await _couple(a, b);
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(a),
        // 스캔 권한과 무관한 서버 알림 경로만 검증한다.
        photoDaysSyncedProvider.overrideWith((ref) async {}),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await a.dispose();
      await b.dispose();
    });
    final sync = container.listen(realtimeSyncProvider, (_, _) {});
    final matched = container.listen(matchedDaysProvider, (_, _) {});
    final photos = container.listen(
      couplePhotosProvider(a.auth.currentUser!.id),
      (_, _) {},
    );
    addTearDown(() {
      sync.close();
      matched.close();
      photos.close();
    });
    await _joined(a, 'couple:$id');
    await _joined(a, 'couple-shares:$id');
    final day = PhotoDay(DateTime(2026, 10, 3), '32060');
    for (final client in [a, b]) {
      (await PhotoDayRepository(client).replaceAll({day: 1})).valueOrThrow;
    }
    (await PhotoSharingRepository(a).replace(id, {day})).valueOrThrow;
    expect(await container.read(matchedDaysProvider.future), isEmpty);
    (await PhotoSharingRepository(
      b,
    ).update(id, approve: {day}, revoke: {})).valueOrThrow;
    await _until(
      () async =>
          (await container.read(matchedDaysProvider.future)).length == 1,
      '상대 승인으로 교집합이 갱신되지 않았어요',
    );
    (await PhotoSharingRepository(
      b,
    ).update(id, approve: {}, revoke: {day})).valueOrThrow;
    await _until(
      () async => (await container.read(matchedDaysProvider.future)).isEmpty,
      '상대 승인 철회로 교집합이 갱신되지 않았어요',
    );
    (await PhotoSharingRepository(
      b,
    ).update(id, approve: {day}, revoke: {})).valueOrThrow;
    await _until(
      () async =>
          (await container.read(matchedDaysProvider.future)).length == 1,
      '상대 재승인으로 교집합이 갱신되지 않았어요',
    );
    (await PhotoDayRepository(b).replaceAll({})).valueOrThrow;
    await _until(
      () async => (await container.read(matchedDaysProvider.future)).isEmpty,
      '원본 삭제의 승인 연쇄 삭제를 읽지 못했어요',
    );
    final tripId = await _trip(b);
    final photo =
        (await b
                .from('photos')
                .insert({
                  'couple_id': id,
                  'trip_id': tripId,
                  'object_key': '$id/$tripId/realtime.jpg',
                  'width': 1,
                  'height': 1,
                  'byte_size': 1,
                  'region_id': '32060',
                  'taken_at': '2026-10-03T12:00:00Z',
                })
                .select('id')
                .single())['id']
            as String;
    final provider = couplePhotosProvider(a.auth.currentUser!.id);
    await _until(
      () async =>
          (await container.read(provider.future)).any((p) => p.id == photo),
      '상대 사진 추가를 읽지 못했어요',
    );
    await b.from('photos').delete().eq('id', photo);
    await _until(
      () async => (await container.read(provider.future)).isEmpty,
      '상대 사진 삭제를 읽지 못했어요',
    );
  }, skip: skip);

  test('커플 알림은 멤버만 받고 승인 알림은 현재 커플만 가입하며 payload에 행을 넣지 않는다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    final outsider = await signUpLocal();
    final otherPartner = await signUpLocal();
    addTearDown(() async {
      await a.dispose();
      await b.dispose();
      await outsider.dispose();
      await otherPartner.dispose();
    });
    final id = await _couple(a, b);
    await _couple(outsider, otherPartner);
    final messages = <Map<String, dynamic>>[];
    await _listen(b, 'couple:$id', messages.add);
    await _listen(b, 'couple-shares:$id', messages.add);
    final publicMessages = <Map<String, dynamic>>[];
    await expectLater(
      _listen(outsider, 'couple:$id', (_) {}),
      throwsA(isA<Object>()),
    );
    await expectLater(
      _listen(outsider, 'couple-shares:$id', (_) {}),
      throwsA(isA<Object>()),
    );
    await expectLater(
      _listen(outsider, 'user:${a.auth.currentUser!.id}', (_) {}),
      throwsA(isA<Object>()),
    );
    await _listen(outsider, 'couple:$id', publicMessages.add, private: false);
    final tripId = await _trip(a);
    await _until(() => messages.any((m) => m['event'] == 'trips'), '여행 알림 미수신');
    messages.clear();
    final rows = await a
        .from('photos')
        .insert([
          for (var i = 0; i < 3; i++)
            {
              'couple_id': id,
              'trip_id': tripId,
              'object_key': '$id/$tripId/$i.jpg',
              'width': 1,
              'height': 1,
              'byte_size': 1,
              'region_id': '32060',
              'taken_at': '2026-10-03T12:00:00Z',
            },
        ])
        .select('id');
    await _until(
      () => messages.where((m) => m['event'] == 'photos').length == 1,
      '일괄 사진 알림 미수신',
    );
    await a
        .from('photos')
        .delete()
        .inFilter('id', rows.map((r) => r['id']).toList());
    await _until(
      () => messages.where((m) => m['event'] == 'photos').length == 2,
      '일괄 삭제 알림 미수신',
    );
    for (final m in messages) {
      final payload = Map<String, dynamic>.from(m['payload'] as Map)
        ..remove('id');
      expect(payload, isEmpty);
    }
    expect(publicMessages, isEmpty);
    final day = PhotoDay(DateTime(2026, 10, 3), '32060');
    (await PhotoDayRepository(a).replaceAll({day: 1})).valueOrThrow;
    (await PhotoSharingRepository(a).replace(id, {day})).valueOrThrow;
    await _until(
      () => messages.any((m) => m['event'] == 'shares'),
      '승인 알림 미수신',
    );
    (await CoupleRepository(a).archive()).valueOrThrow;
    await _until(
      () => messages.any((m) => m['event'] == 'couple'),
      '아카이브 알림 미수신',
    );
    messages.clear();
    // 가입 시 캐시된 권한이 남아 있어도 원본 연쇄 삭제는 빈 무효화 알림뿐이다.
    (await PhotoDayRepository(a).replaceAll({})).valueOrThrow;
    await _until(
      () => messages.any((m) => m['event'] == 'shares'),
      '기존 승인 채널의 연쇄 삭제 알림 미수신',
    );
    for (final m in messages) {
      final payload = Map<String, dynamic>.from(m['payload'] as Map)
        ..remove('id');
      expect(payload, isEmpty);
    }
    await b.removeAllChannels();
    await _listen(b, 'couple:$id', (_) {});
    await expectLater(
      _listen(b, 'couple-shares:$id', (_) {}),
      throwsA(isA<Object>()),
    );
  }, skip: skip);
  test('이벤트별 조회만 무효화하고 재연결·복귀를 보완하며 이전 계정 콜백을 차단한다', () async {
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    final a = await signUpLocal();
    final b = await signUpLocal();
    final replacement = await signUpLocal();
    final id = await _couple(a, b);
    final userId = a.auth.currentUser!.id;
    final reads = <String, int>{};
    void count(String name) =>
        reads.update(name, (n) => n + 1, ifAbsent: () => 1);
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(a),
        tripsProvider.overrideWith((ref) async {
          count('trips');
          return [];
        }),
        overridesProvider.overrideWith((ref) async {
          count('overrides');
          return {};
        }),
        matchedDaysProvider.overrideWith((ref) async {
          count('shares');
          return [];
        }),
        couplePhotosProvider.overrideWith((ref, userId) async {
          count('photos');
          return [];
        }),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await a.dispose();
      await b.dispose();
      await replacement.dispose();
    });
    final sync = container.listen(realtimeSyncProvider, (_, _) {});
    final subscriptions = [
      container.listen(tripsProvider, (_, _) {}),
      container.listen(overridesProvider, (_, _) {}),
      container.listen(matchedDaysProvider, (_, _) {}),
      container.listen(couplePhotosProvider(userId), (_, _) {}),
    ];
    addTearDown(() {
      sync.close();
      for (final s in subscriptions) {
        s.close();
      }
    });
    final couple = await _joined(a, 'couple:$id');
    final shares = await _joined(a, 'couple-shares:$id');
    final user = await _joined(a, 'user:$userId');
    Future<void> settle() async {
      await container.pump();
      await container.read(currentCoupleProvider.future);
      await container.pump();
      await Future.wait([
        container.read(tripsProvider.future),
        container.read(overridesProvider.future),
        container.read(matchedDaysProvider.future),
        container.read(couplePhotosProvider(userId).future),
      ]);
    }

    await settle();
    for (final event in ['photos', 'trips', 'overrides', 'shares']) {
      final before = Map<String, int>.of(reads);
      _deliver(event == 'shares' ? shares : couple, event);
      await settle();
      expect(reads[event], before[event]! + 1);
      for (final other in before.keys.where((k) => k != event)) {
        expect(
          reads[other],
          before[other],
          reason: '$event 알림으로 $other 조회를 반복하지 않는다',
        );
      }
    }
    final beforeReconnect = Map<String, int>.of(reads);
    final channels = [user, couple, shares];
    final previousJoins = {
      for (final channel in channels) channel: channel.joinRef,
    };
    // 정상 disconnect는 자동 재가입을 막으므로 실제 전송 연결을 끊는다.
    await a.realtime.conn!.sink.close();
    await _until(
      () => channels.every(
        (channel) =>
            channel.isJoined && channel.joinRef != previousJoins[channel],
      ),
      '연결 단절 후 private 채널이 새 join으로 재가입하지 않았어요',
    );
    await _until(
      () => reads['shares']! > beforeReconnect['shares']!,
      '재연결 조회 누락',
    );
    await settle();
    expect(reads['photos'], greaterThan(beforeReconnect['photos']!));
    final beforeBroadcast = reads['overrides']!;
    await b.from('couple_region_overrides').insert({
      'couple_id': id,
      'region_id': '32060',
      'kind': 'home',
    });
    await _until(
      () => reads['overrides']! > beforeBroadcast,
      '재가입 후 실제 알림 미수신',
    );
    final beforeResume = Map<String, int>.of(reads);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      WidgetsBinding.instance.handleAppLifecycleStateChanged(state);
    }
    await settle();
    expect(reads['photos'], greaterThan(beforeResume['photos']!));
    expect(reads['shares'], greaterThan(beforeResume['shares']!));

    await a.auth.setSession(replacement.auth.currentSession!.refreshToken!);
    await _joined(a, 'user:${replacement.auth.currentUser!.id}');
    await _until(
      () =>
          !a.getChannels().contains(couple) &&
          !a.getChannels().contains(shares),
      '이전 계정 채널이 남아 있어요',
    );
    await settle();
    final afterSwitch = Map<String, int>.of(reads);
    _deliver(couple, 'photos');
    _deliver(couple, 'trips');
    _deliver(shares, 'shares');
    _deliver(user, 'membership');
    await settle();
    expect(reads, afterSwitch, reason: '늦은 이전 계정 콜백이 새 계정 조회를 건드리지 않는다');
    expect(await container.read(currentCoupleProvider.future), isNull);
  }, skip: skip);
}
