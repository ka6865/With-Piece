import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/signed_url_cache.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/features/album/album_providers.dart';

void main() {
  test('없는 경로만 묶어 발급하고 만료 5분 전이면 다시 받는다', () async {
    var now = DateTime(2026, 11, 1, 9);
    final requests = <List<String>>[];
    final cache = SignedUrlCache((paths) async {
      requests.add(paths);
      return {for (final p in paths) p: '$p?t=${requests.length}'};
    }, now: () => now);

    expect(await cache.urls(['a', 'b']), {'a': 'a?t=1', 'b': 'b?t=1'});
    expect(await cache.urls(['a', 'c']), {'a': 'a?t=1', 'c': 'c?t=2'});
    expect(requests, [
      ['a', 'b'],
      ['c'],
    ]);

    now = now.add(const Duration(minutes: 56));
    expect((await cache.urls(['a']))['a'], 'a?t=3');
  });

  test('같은 커플 아카이브도 계정별 FutureProvider family 상태를 공유하지 않는다', () async {
    final releaseB = Completer<void>();
    const a = (userId: 'user-a', coupleId: 'same-couple');
    const b = (userId: 'user-b', coupleId: 'same-couple');
    final photoA = PhotoRecord(
      id: 'photo-a',
      tripId: 'trip',
      regionId: null,
      objectKey: 'same-couple/trip/photo-a.jpg',
      uploadedBy: 'user-a',
      takenAt: null,
      width: 1,
      height: 1,
    );
    final photoB = PhotoRecord(
      id: 'photo-b',
      tripId: 'trip',
      regionId: null,
      objectKey: 'same-couple/trip/photo-b.jpg',
      uploadedBy: 'user-b',
      takenAt: null,
      width: 1,
      height: 1,
    );
    final container = ProviderContainer(
      overrides: [
        archivedPhotosProvider(a).overrideWith((ref) async => [photoA]),
        archivedPhotosProvider(b).overrideWith((ref) async {
          await releaseB.future;
          return [photoB];
        }),
      ],
    );
    expect(await container.read(archivedPhotosProvider(a).future), [photoA]);
    final bState = container.read(archivedPhotosProvider(b));
    expect(bState.isLoading, isTrue);
    expect(bState.value, isNull);
    releaseB.complete();
    expect(await container.read(archivedPhotosProvider(b).future), [photoB]);
    container.dispose();
  });

  test('같은 ProviderContainer에서 계정이 바뀌면 서명 URL 캐시를 교체한다', () async {
    final sessions = StreamController<Session?>.broadcast();
    final client = SupabaseClient('http://127.0.0.1:1', 'unused');
    final container = ProviderContainer(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        sessionProvider.overrideWith((ref) => sessions.stream),
      ],
    );
    final subscription = container.listen(sessionProvider, (_, _) {});
    Session session(String id) => Session(
      accessToken: id,
      tokenType: 'bearer',
      user: User(
        id: id,
        appMetadata: const {},
        userMetadata: null,
        aud: 'authenticated',
        createdAt: '',
      ),
    );

    sessions.add(session('user-a'));
    await Future<void>.delayed(Duration.zero);
    final first = container.read(signedUrlCacheProvider);
    sessions.add(session('user-b'));
    await Future<void>.delayed(Duration.zero);
    final second = container.read(signedUrlCacheProvider);

    expect(identical(first, second), isFalse);
    subscription.close();
    container.dispose();
    await sessions.close();
    await client.dispose();
  });
}
