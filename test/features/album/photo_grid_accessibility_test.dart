import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/signed_url_cache.dart';
import 'package:woori_piece/features/album/album_providers.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/album/photo_grid.dart';

void main() {
  testWidgets('사진 격자 항목은 스크린 리더에 사진 순번으로 노출된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          sessionUserIdProvider.overrideWithValue('user'),
          signedUrlCacheProvider.overrideWithValue(
            SignedUrlCache(
              (paths) async => {
                for (final path in paths) path: 'https://example.com/$path',
              },
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PhotoGrid(
              photos: [
                PhotoRecord(
                  id: 'p1',
                  tripId: 't1',
                  regionId: null,
                  objectKey: 'c/t/p.jpg',
                  uploadedBy: 'user',
                  takenAt: null,
                  width: 10,
                  height: 10,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('사진 1'), findsOneWidget);
  });
}
