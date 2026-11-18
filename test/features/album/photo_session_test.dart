import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/signed_url_cache.dart';
import 'package:woori_piece/features/album/album_providers.dart';
import 'package:woori_piece/features/album/photo_grid.dart';

void main() {
  testWidgets('사진 확대 화면도 계정이 바뀌면 이전 사진을 숨긴다', (tester) async {
    final users = StreamController<String?>.broadcast();
    final userStream = StreamProvider<String?>((ref) => users.stream);
    final container = ProviderContainer(
      overrides: [
        sessionUserIdProvider.overrideWith(
          (ref) => ref.watch(userStream).value,
        ),
        signedUrlCacheProvider.overrideWithValue(
          SignedUrlCache(
            (paths) async => {
              for (final p in paths) p: 'https://example.com/$p',
            },
          ),
        ),
      ],
    );
    final photo = PhotoRecord(
      id: 'p',
      tripId: 't',
      regionId: '32060',
      objectKey: 'c/t/p.jpg',
      uploadedBy: 'a',
      takenAt: DateTime(2026),
      width: 100,
      height: 100,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: PhotoGrid(photos: [photo])),
        ),
      ),
    );
    users.add('a');
    await tester.pumpAndSettle();
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    users.add('b');
    await tester.pumpAndSettle();
    expect(find.text('계정이 바뀌어 사진을 닫았어요'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
    await tester.runAsync(users.close);
  });
}
