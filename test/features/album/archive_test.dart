import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/app/app.dart';
import 'package:woori_piece/app/router.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/signed_url_cache.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/album/album_providers.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/scan/realtime_sync.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'package:woori_piece/map_data/map_asset.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';

final provinces = MapAsset.parse(
  File('assets/map/provinces_v1.json').readAsStringSync(),
);
final regions = MapAsset.parse(
  File('assets/map/regions_v1.json').readAsStringSync(),
);

Future<void> pumpApp(WidgetTester tester, String location) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        realtimeSyncProvider.overrideWith((ref) {}),
        appStageProvider.overrideWithValue(AppStage.needsCouple),
        initialLocationProvider.overrideWithValue(location),
        provinceMapAssetProvider.overrideWith((ref) => provinces),
        regionMapAssetProvider.overrideWith((ref) => regions),
        sessionUserIdProvider.overrideWithValue('me'),
        archivedCouplesProvider('me').overrideWith(
          (ref) async => [
            ArchivedCouple(
              id: 'c-old',
              partnerName: '지난 연인',
              archivedAt: DateTime(2026, 11, 1),
              partnerDeletionDate: DateTime(2026, 12, 1),
            ),
          ],
        ),
        archivedTripsProvider((userId: 'me', coupleId: 'c-old')).overrideWith(
          (ref) async => [
            Trip(
              id: 't1',
              title: '경주시',
              range: DateRange(DateTime(2026, 5, 1), DateTime(2026, 5, 1)),
              status: TripStatus.confirmed,
              source: TripSource.auto,
              regionIds: const ['37020'],
            ),
          ],
        ),
        archivedPhotosProvider((userId: 'me', coupleId: 'c-old')).overrideWith(
          (ref) async => [
            PhotoRecord(
              id: 'p1',
              tripId: 't1',
              regionId: '37020',
              objectKey: 'c-old/t1/p1.heic',
              uploadedBy: 'me',
              takenAt: DateTime(2026, 5, 1),
              width: 1,
              height: 1,
            ),
          ],
        ),
        signedUrlCacheProvider.overrideWithValue(
          SignedUrlCache(
            (paths) async => {for (final p in paths) p: 'https://x/$p'},
          ),
        ),
      ],
      child: const WooriPieceApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('지난 기록에 아카이브된 커플과 삭제 예정일이 보인다', (tester) async {
    await pumpApp(tester, '/archive');
    expect(find.text('지난 연인'), findsOneWidget);
    expect(find.textContaining('12월 1일에 사라져요'), findsOneWidget);
  });

  testWidgets('지난 기록의 여행은 읽기 전용이다', (tester) async {
    await pumpApp(tester, '/archive/c-old/trips/t1');
    expect(find.text('경주시'), findsWidgets);
    expect(find.byTooltip('사진 지우기'), findsNothing);
    expect(find.byTooltip('제목 바꾸기'), findsNothing);
    expect(find.text('사진 더하기'), findsNothing);
    expect(find.text('조각 추가'), findsNothing);
  });

  testWidgets('지난 기록의 앨범은 그 커플의 여행을 보여준다', (tester) async {
    await pumpApp(tester, '/archive/c-old');
    expect(find.text('경주시'), findsOneWidget);
    await tester.tap(find.text('경주시'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trip-detail')), findsOneWidget);
  });
}
