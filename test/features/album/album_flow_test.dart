import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/app/app.dart';
import 'package:woori_piece/app/router.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/signed_url_cache.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/album/album_providers.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/features/map/view/province_map_page.dart';
import 'package:woori_piece/features/map/view/puzzle_map.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'package:woori_piece/map_data/map_asset.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';

final provinces = MapAsset.parse(
  File('assets/map/provinces_v1.json').readAsStringSync(),
);
final regions = MapAsset.parse(
  File('assets/map/regions_v1.json').readAsStringSync(),
);

Trip trip(
  String id,
  String title,
  int day,
  List<String> regionIds, {
  TripStatus status = TripStatus.confirmed,
}) => Trip(
  id: id,
  title: title,
  range: DateRange(DateTime(2026, 10, day), DateTime(2026, 10, day)),
  status: status,
  source: TripSource.auto,
  regionIds: regionIds,
);

PhotoRecord photo(String id, String tripId, String uploadedBy) => PhotoRecord(
  id: id,
  tripId: tripId,
  regionId: '32060',
  objectKey: 'c1/$tripId/$id.heic',
  uploadedBy: uploadedBy,
  takenAt: DateTime(2026, 10, 3),
  width: 2048,
  height: 1536,
);

final trips = [
  trip('old', '경주시', 1, ['37020']),
  trip('gone', '버린 여행', 2, [], status: TripStatus.dismissed),
  trip('t3', '속초시', 3, ['32060']),
  trip('also', '속초시 다시', 5, ['32060']),
];

Future<void> pumpApp(WidgetTester tester, String location) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStageProvider.overrideWithValue(AppStage.ready),
        initialLocationProvider.overrideWithValue(location),
        provinceMapAssetProvider.overrideWith((ref) => provinces),
        regionMapAssetProvider.overrideWith((ref) => regions),
        currentCoupleProvider.overrideWith(
          (ref) async => const Couple(id: 'c1', partnerId: 'p'),
        ),
        currentUserIdProvider.overrideWithValue('me'),
        tripsProvider.overrideWith((ref) async => trips),
        homeRegionIdsProvider.overrideWith((ref) async => const {}),
        tripCandidatesProvider.overrideWith((ref) async => const []),
        couplePhotosProvider.overrideWith(
          (ref) async => [
            photo('p1', 't3', 'me'),
            photo('p2', 't3', 'partner'),
            photo('p3', 'old', 'me'),
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
  testWidgets('앨범은 확인된 여행만 최신순으로 사진 수와 함께 보인다', (tester) async {
    await pumpApp(tester, '/album');
    final titles = tester
        .widgetList<Text>(find.byKey(const Key('album-title')))
        .map((t) => t.data)
        .toList();
    expect(titles, ['속초시 다시', '속초시', '경주시']);
    expect(find.textContaining('사진 2장'), findsOneWidget);
  });

  testWidgets('여행 상세에서 내 사진만 지울 수 있다', (tester) async {
    await pumpApp(tester, '/trips/t3');
    expect(find.text('속초시'), findsWidgets);
    expect(find.byTooltip('사진 지우기'), findsOneWidget);
  });

  testWidgets('칠해진 조각을 탭하면 여행이 여럿일 때 목록에서 고른다', (tester) async {
    await pumpApp(tester, '/province/32');
    final box = tester.renderObject<RenderBox>(find.byType(PuzzleMap));
    final layout = PuzzleLayout.build(
      asset: provinceAssetOf(regions, '32')!,
      size: box.size,
    );
    await tester.tapAt(box.localToGlobal(layout.labelPoints['32060']!));
    await tester.pumpAndSettle();
    expect(find.text('속초시 다시'), findsOneWidget);
    await tester.tap(find.text('속초시 다시'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trip-detail')), findsOneWidget);
  });

  testWidgets('/trips/candidates는 여행 상세가 아니라 후보 화면을 연다', (tester) async {
    await pumpApp(tester, '/trips/candidates');
    expect(find.text('함께 간 여행'), findsOneWidget);
    expect(find.byKey(const Key('trip-detail')), findsNothing);
  });
}
