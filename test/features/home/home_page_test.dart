import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woori_piece/app/app.dart';
import 'package:woori_piece/app/router.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/refresh_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/data/repositories/signed_url_cache.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/album/album_providers.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/home/couple_days.dart';
import 'package:woori_piece/features/home/home_page.dart';
import 'package:woori_piece/features/home/rewind_page.dart';
import 'package:woori_piece/features/map/view/mini_puzzle_map.dart';
import 'package:woori_piece/features/map/view/puzzle_map.dart';
import 'package:woori_piece/features/refresh/refresh_providers.dart';
import 'package:woori_piece/features/scan/realtime_sync.dart';
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

Trip trip(String id, String title, int day, List<String> regionIds) => Trip(
  id: id,
  title: title,
  range: DateRange(DateTime(2026, 10, day), DateTime(2026, 10, day)),
  status: TripStatus.confirmed,
  source: TripSource.auto,
  regionIds: regionIds,
);

PhotoRecord photo(String id, String tripId) => PhotoRecord(
  id: id,
  tripId: tripId,
  regionId: '32060',
  objectKey: 'c1/$tripId/$id.heic',
  uploadedBy: 'me',
  takenAt: DateTime(2026, 10, 3),
  width: 2048,
  height: 1536,
);

final startedOn = DateTime(2025, 6, 24);

Future<void> pumpApp(
  WidgetTester tester, {
  AppStage stage = AppStage.ready,
  String location = '/',
  List<Trip> trips = const [],
  List<TripCandidate> candidates = const [],
  bool rewindSeen = true,
  List<String>? seenPieces,
  Map<String, RefreshState> refreshStates = const {},
  RefreshRepository? refreshRepository,
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({
    if (rewindSeen) RewindGate.seenKey('me', 'c1'): true,
    HomePage.seenPiecesKey('me', 'c1'): ?seenPieces,
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        realtimeSyncProvider.overrideWith((ref) {}),
        sharedPreferencesProvider.overrideWithValue(prefs),
        appStageProvider.overrideWithValue(stage),
        initialLocationProvider.overrideWithValue(location),
        provinceMapAssetProvider.overrideWith((ref) => provinces),
        regionMapAssetProvider.overrideWith((ref) => regions),
        currentCoupleProvider.overrideWith(
          (ref) async => Couple(
            id: 'c1',
            partnerId: 'p',
            startedOn: startedOn,
            myName: '민지',
            partnerName: '준호',
          ),
        ),
        sessionUserIdProvider.overrideWithValue('me'),
        tripsProvider.overrideWith((ref) async => [...trips]),
        refreshStatesProvider.overrideWith((ref) async => refreshStates),
        if (refreshRepository != null)
          refreshRepositoryProvider.overrideWithValue(refreshRepository),
        homeRegionIdsProvider.overrideWith((ref) async => {'11010'}),
        tripCandidatesProvider.overrideWith((ref) async => candidates),
        couplePhotosProvider(
          'me',
        ).overrideWith((ref) async => [photo('p1', 't2'), photo('p2', 't2')]),
        signedUrlCacheProvider.overrideWithValue(
          SignedUrlCache(
            (paths) async => {for (final p in paths) p: 'https://x/$p'},
          ),
        ),
      ],
      child: const WooriPieceApp(),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  testWidgets('홈은 함께한 날, 두 사람, 채운 조각 수를 보여준다', (tester) async {
    await pumpApp(
      tester,
      trips: [
        trip('t1', '경주시', 1, ['37020']),
        trip('t2', '속초시', 3, ['32060', '32030']),
      ],
    );
    expect(
      find.text('D+${daysTogether(startedOn, DateTime.now())}'),
      findsOneWidget,
    );
    expect(find.text('2025.06.24부터 함께'), findsOneWidget);
    expect(find.text('민'), findsOneWidget);
    expect(find.text('준'), findsOneWidget);
    // 여행 조각 3개와 생활권 1개, 분모는 애셋의 조각 수
    expect(find.text('4 / ${regions.features.length}'), findsOneWidget);
    final mini = tester.widget<MiniPuzzleMap>(find.byType(MiniPuzzleMap));
    expect(mini.visitedRegionIds, {'37020', '32060', '32030', '11010'});
    // 최근 여행은 가장 늦게 시작한 여행
    expect(find.text('속초시'), findsOneWidget);
    expect(find.text('경주시'), findsNothing);
  });

  testWidgets('여행이 없으면 첫 여행 안내를 보여준다', (tester) async {
    await pumpApp(tester);
    expect(find.text('첫 여행을 여기 담아볼까요?'), findsOneWidget);
    expect(find.text('전체'), findsNothing);
  });

  testWidgets('여행 발견 안내는 지도가 아니라 홈에 있다', (tester) async {
    await pumpApp(
      tester,
      candidates: [
        TripCandidate(
          range: DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 1)),
          regionIds: const ['32060'],
          title: '속초시',
        ),
      ],
    );
    expect(find.text('함께 간 여행 1개를 찾았어요'), findsOneWidget);
    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();
    expect(find.text('우리들의 조각'), findsOneWidget);
    expect(find.text('함께 간 여행 1개를 찾았어요'), findsNothing);
  });

  testWidgets('로그인·커플 확인 전에는 빈 지도를 먼저 그리지 않는다', (tester) async {
    await pumpApp(tester, stage: AppStage.loading, settle: false);
    expect(find.byType(MiniPuzzleMap), findsNothing);
  });

  testWidgets('홈의 ?를 누르면 홈 도움말을 보여준다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('도움말'));
    // 도움말 그림은 되풀이 애니메이션이라 가라앉지 않는다
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('홈 도움말'), findsOneWidget);
  });

  testWidgets('우리의 조각 카드를 누르면 지도 탭으로 간다', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('우리의 조각'));
    await tester.pumpAndSettle();
    expect(find.text('우리들의 조각'), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 1);
  });

  testWidgets('커플 조회에 실패해도 앨범에서 하단 탭으로 지도에 갈 수 있다', (tester) async {
    await pumpApp(tester, stage: AppStage.unavailable, location: '/album');
    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();
    expect(find.text('우리들의 조각'), findsOneWidget);
  });

  testWidgets('처음 홈에 들어오면 사귄 날로 되감은 뒤 홈으로 돌아온다', (tester) async {
    await pumpApp(tester, rewindSeen: false, settle: false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(RewindPage), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(RewindPage), findsNothing);
    expect(find.text('우리의 조각'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(RewindGate.seenKey('me', 'c1')), isTrue);
  });

  testWidgets('되감기 중간에 사귄 날에 멈추고 건너뛸 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RewindPage(
                  startedOn: DateTime(2025, 6, 24),
                  today: DateTime(2026, 11, 20),
                ),
              ),
            ),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pump();
    final dPlus = find.text(
      'D+${daysTogether(DateTime(2025, 6, 24), DateTime(2026, 11, 20))}',
    );
    // 사귄 날에 닿은 뒤 1초 동안 머문다
    await tester.pump(const Duration(milliseconds: 4600));
    expect(find.text('2025.06.24'), findsOneWidget);
    expect(find.text('우리가 시작한 날'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('2025.06.24'), findsOneWidget);
    // 세어 올라온 D+N에서 마지막 1초 동안 머문다
    await tester.pump(const Duration(milliseconds: 2700));
    expect(dPlus, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(dPlus, findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('열기'), findsOneWidget);
    await tester.tap(find.text('열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    expect(find.byType(RewindPage), findsNothing);
  });

  testWidgets('동작 줄이기를 켜면 되감지 않고 본 것으로 남긴다', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(tester, rewindSeen: false);
    expect(find.byType(RewindPage), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(RewindGate.seenKey('me', 'c1')), isTrue);
  });

  testWidgets('이미 본 사람에게는 되감기를 다시 보이지 않는다', (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(RewindPage), findsNothing);
  });

  testWidgets('마지막으로 본 뒤 새로 채운 조각만 홈 지도에서 맞춰 넣는다', (tester) async {
    await pumpApp(
      tester,
      trips: [
        trip('t1', '경주시', 1, ['37020']),
      ],
      seenPieces: ['11010'],
    );
    final mini = tester.widget<MiniPuzzleMap>(find.byType(MiniPuzzleMap));
    expect(mini.snapRegionIds, {'37020'});
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(HomePage.seenPiecesKey('me', 'c1'))?.toSet(), {
      '11010',
      '37020',
    });
  });

  testWidgets('처음 보는 기기는 맞춤 연출 없이 지금 조각을 기준으로 남긴다', (tester) async {
    await pumpApp(
      tester,
      trips: [
        trip('t1', '경주시', 1, ['37020']),
      ],
    );
    final mini = tester.widget<MiniPuzzleMap>(find.byType(MiniPuzzleMap));
    expect(mini.snapRegionIds, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(HomePage.seenPiecesKey('me', 'c1'))?.toSet(), {
      '11010',
      '37020',
    });
  });

  testWidgets('홈이 가려진 동안 상대가 채운 조각은 홈으로 돌아올 때 맞춰 넣는다', (tester) async {
    final trips = <Trip>[];
    await pumpApp(tester, trips: trips, seenPieces: ['11010']);
    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();
    // Realtime 반영을 흉내 낸다
    trips.add(trip('t1', '경주시', 1, ['37020']));
    ProviderScope.containerOf(
      tester.element(find.byType(NavigationBar)),
    ).invalidate(tripsProvider);
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(HomePage.seenPiecesKey('me', 'c1'))?.toSet(), {
      '11010',
    });
    await tester.tap(find.text('홈'));
    await tester.pumpAndSettle();
    final mini = tester.widget<MiniPuzzleMap>(find.byType(MiniPuzzleMap));
    expect(mini.snapRegionIds, {'37020'});
  });

  testWidgets('동작 줄이기를 켜면 조각 맞춤 없이 기준만 갱신한다', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(
      tester,
      trips: [
        trip('t1', '경주시', 1, ['37020']),
      ],
      seenPieces: ['11010'],
    );
    final mini = tester.widget<MiniPuzzleMap>(find.byType(MiniPuzzleMap));
    expect(mini.snapRegionIds, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(HomePage.seenPiecesKey('me', 'c1'))?.toSet(), {
      '11010',
      '37020',
    });
  });

  testWidgets('전국 지도는 시도가 아니라 채운 조각을 칠한다', (tester) async {
    await pumpApp(
      tester,
      trips: [
        trip('t1', '속초시', 1, ['32060']),
      ],
    );
    await tester.tap(find.text('지도'));
    await tester.pumpAndSettle();
    final map = tester.widget<PuzzleMap>(find.byType(PuzzleMap));
    expect(map.visitedRegionIds, {'32060'});
    expect(map.homeRegionIds, {'11010'});
  });

  testWidgets('상대가 보낸 최신화 요청은 홈 카드와 탭 점으로 알린다', (tester) async {
    await pumpApp(
      tester,
      refreshStates: {
        'me': RefreshState(requestedAt: DateTime.now(), requestedBy: 'p'),
      },
    );
    expect(find.text('준호님이 여행 최신화를 요청했어요'), findsOneWidget);
    final badge = tester.widget<Badge>(
      find.ancestor(of: find.byIcon(Icons.sync), matching: find.byType(Badge)),
    );
    expect(badge.isLabelVisible, isTrue);
    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    expect(find.text('준호님이 여행 최신화를 요청했어요'), findsNothing);
    await tester.tap(find.text('최신화'));
    await tester.pumpAndSettle();
    // 나중에는 홈 카드만 숨기고 탭에서는 계속 보인다
    expect(find.text('준호님이 여행 최신화를 요청했어요'), findsOneWidget);
  });

  testWidgets('최신화 탭은 상대 상태를 보이고 요청을 보낸다', (tester) async {
    final repository = _FakeRefreshRepository();
    await pumpApp(
      tester,
      location: '/refresh',
      refreshRepository: repository,
      refreshStates: {
        'p': RefreshState(
          refreshedAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      },
    );
    expect(find.text('준호님은 3일 전에 마지막으로 최신화했어요'), findsOneWidget);
    await tester.tap(find.text('준호님에게 최신화 요청하기'));
    await tester.pumpAndSettle();
    expect(repository.requests, 1);
    expect(find.text('준호님에게 최신화를 요청했어요'), findsOneWidget);
  });

  testWidgets('방금 요청한 상대에게는 다시 요청하지 못한다', (tester) async {
    await pumpApp(
      tester,
      location: '/refresh',
      refreshStates: {
        'p': RefreshState(requestedAt: DateTime.now(), requestedBy: 'me'),
      },
    );
    expect(find.text('준호님의 최신화 기록이 아직 없어요'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('요청을 보냈어요'),
        matching: find.byWidgetPredicate((w) => w is FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
  });
}

class _FakeRefreshRepository implements RefreshRepository {
  int requests = 0;

  @override
  Future<Result<void>> request() async {
    requests++;
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
