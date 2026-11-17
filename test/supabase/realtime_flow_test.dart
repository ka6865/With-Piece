import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/scan/realtime_sync.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'support.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final skip = await localStackSkipReason();
  test(
    '대기 중 상대 합류를 다시 읽고 사진 추가·삭제 이벤트를 받는다',
    () async {
      final a = await signUpLocal();
      final b = await signUpLocal();
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(a),
          sessionProvider.overrideWith(
            (ref) => Stream.value(a.auth.currentSession),
          ),
          coupleRepositoryProvider.overrideWithValue(CoupleRepository(a)),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await a.dispose();
        await b.dispose();
      });
      final sync = container.listen(realtimeSyncProvider, (_, _) {});
      addTearDown(sync.close);
      expect(await container.read(currentCoupleProvider.future), isNull);
      await CoupleRepository(
        b,
      ).join((await CoupleRepository(a).createInvite()).valueOrThrow.code);
      final limit = DateTime.now().add(const Duration(seconds: 12));
      Couple? couple;
      while (DateTime.now().isBefore(limit)) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
        couple = await container.read(currentCoupleProvider.future);
        if (couple != null) break;
      }
      expect(couple, isNotNull);
      final tripId = (await TripRepository(a).confirm(
        title: '속초시',
        range: DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 3)),
        regionIds: ['32060'],
        source: TripSource.manual,
      )).valueOrThrow;
      final inserted = Completer<void>();
      final deleted = Completer<void>();
      final replicationReady = Completer<void>();
      final channel = b.channel('realtime-test-$tripId')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'photos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'couple_id',
            value: couple!.id,
          ),
          callback: (payload) {
            if (payload.eventType == PostgresChangeEvent.insert &&
                !inserted.isCompleted) {
              inserted.complete();
            }
            if (payload.eventType == PostgresChangeEvent.delete &&
                !deleted.isCompleted) {
              deleted.complete();
            }
          },
        );
      // 채널 가입 응답 뒤에 PostgreSQL 구독이 따로 준비된다.
      channel.onSystemEvents((payload) {
        if (payload is Map &&
            payload['extension'] == 'postgres_changes' &&
            payload['status'] == 'ok' &&
            !replicationReady.isCompleted) {
          replicationReady.complete();
        }
      });
      RealtimeSubscribeStatus? lastStatus;
      channel.subscribe((status, [_]) => lastStatus = status);
      addTearDown(() => b.removeChannel(channel));
      await replicationReady.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('사진 변경 구독이 준비되지 않았어요 ($lastStatus)'),
      );
      final id =
          (await a
                  .from('photos')
                  .insert({
                    'couple_id': couple.id,
                    'trip_id': tripId,
                    'object_key': '${couple.id}/$tripId/realtime.jpg',
                    'width': 1,
                    'height': 1,
                    'byte_size': 1,
                  })
                  .select('id')
                  .single())['id']
              as String;
      await inserted.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('사진 추가 이벤트를 받지 못했어요 ($lastStatus)'),
      );
      await a.from('photos').delete().eq('id', id);
      await deleted.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('사진 삭제 이벤트를 받지 못했어요 ($lastStatus)'),
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
