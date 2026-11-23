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
import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/features/map/view/province_map_page.dart';
import 'package:woori_piece/features/map/view/puzzle_map.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'package:woori_piece/map_data/map_asset.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import '../trip/fakes.dart';

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

Future<void> pumpApp(
  WidgetTester tester,
  String location, {
  TripRepository? tripRepository,
  List<Trip>? tripList,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(testPrefs),
        realtimeSyncProvider.overrideWith((ref) {}),
        appStageProvider.overrideWithValue(AppStage.ready),
        initialLocationProvider.overrideWithValue(location),
        provinceMapAssetProvider.overrideWith((ref) => provinces),
        regionMapAssetProvider.overrideWith((ref) => regions),
        currentCoupleProvider.overrideWith(
          (ref) async => const Couple(id: 'c1', partnerId: 'p'),
        ),
        sessionUserIdProvider.overrideWithValue('me'),
        if (tripRepository != null)
          tripRepositoryProvider.overrideWithValue(tripRepository),
        tripsProvider.overrideWith((ref) async => tripList ?? trips),
        homeRegionIdsProvider.overrideWith((ref) async => const {}),
        tripCandidatesProvider.overrideWith((ref) async => const []),
        couplePhotosProvider('me').overrideWith(
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

// 사진 격자의 칸 수 기억(PinchColumns)이 읽는다
late SharedPreferences testPrefs;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testPrefs = await SharedPreferences.getInstance();
  });

  testWidgets('앨범은 확인된 여행만 최신순으로 사진 수와 함께 보인다', (tester) async {
    // 2열 격자가 세 여행을 모두 그리도록 화면을 세로로 길게 둔다
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
    expect(find.text('사진 추가하기'), findsOneWidget);
  });

  testWidgets('휴지통에서 내 사진만 골라 확인을 받고 지운다', (tester) async {
    await pumpApp(tester, '/trips/t3');
    await tester.tap(find.byTooltip('사진 지우기'));
    await tester.pumpAndSettle();
    // t3에서 내가 올린 사진은 p1 하나다
    expect(find.bySemanticsLabel('사진 고르기'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('사진 고르기'));
    await tester.pump();
    expect(find.text('1장 선택'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '지우기'));
    await tester.pumpAndSettle();
    expect(find.text('사진 1장을 정말 지우시겠습니까?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('1장 선택'), findsOneWidget);
  });

  testWidgets('여행을 지우면 상대 사진까지 지워진다고 묻고, 지운 뒤 앨범으로 돌아간다', (tester) async {
    final repo = FakeTripRepository();
    // 2열 격자가 여행 카드를 모두 그리도록 화면을 세로로 길게 둔다
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(tester, '/album', tripRepository: repo);
    await tester.tap(find.text('속초시'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('여행 지우기'));
    await tester.pumpAndSettle();
    // t3에는 내 사진 p1과 상대 사진 p2가 있다
    expect(find.textContaining('두 사람이 올린 사진 2장'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.deletedTrips, isEmpty);
    await tester.tap(find.byTooltip('여행 지우기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '지우기'));
    await tester.pumpAndSettle();
    expect(repo.deletedTrips, ['t3']);
    // 내 파일만 바로 지운다. 상대 파일은 정리 작업이 지운다
    expect(repo.deletedFiles, ['p1']);
    expect(find.byKey(const Key('trip-detail')), findsNothing);
  });

  testWidgets('여행에서 조각을 빼기 전에 한 번 더 묻는다', (tester) async {
    final repo = FakeTripRepository();
    await pumpApp(
      tester,
      '/trips/two',
      tripRepository: repo,
      tripList: [
        trip('two', '강릉과 속초', 7, ['32030', '32060']),
      ],
    );
    await tester.tap(find.byIcon(Icons.clear).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('여행에서 뺄까요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(repo.removed, isEmpty);
    await tester.tap(find.byIcon(Icons.clear).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '빼기'));
    await tester.pumpAndSettle();
    expect(repo.removed, hasLength(1));
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
