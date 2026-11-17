import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/data/repositories/signed_url_cache.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/album/album_page.dart';
import 'package:woori_piece/features/album/album_providers.dart';
import 'package:woori_piece/features/auth/account_links_page.dart';
import 'package:woori_piece/features/auth/account_state.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/map/view/national_map_page.dart';
import 'package:woori_piece/features/map/view/province_map_page.dart';
import 'package:woori_piece/features/map/view/puzzle_map.dart';
import 'package:woori_piece/features/scan/realtime_sync.dart';
import 'package:woori_piece/features/scan/scan_store.dart';
import 'package:woori_piece/features/scan/scan_sync.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'package:woori_piece/features/trip/photo_upload_page.dart';

import '../../features/auth/fakes.dart';
import '../../features/trip/fakes.dart';
import 'package:woori_piece/map_data/map_asset.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';

class _User extends Notifier<String?> {
  @override
  String? build() => 'a';
  void set(String? value) => state = value;
}

final _user = NotifierProvider<_User, String?>(_User.new);
final _trip = Trip(
  id: 'trip-a',
  title: '이전 여행',
  range: DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 1)),
  status: TripStatus.confirmed,
  source: TripSource.auto,
  regionIds: const ['32060'],
);

class _Trips extends FakeTripRepository {
  Future<Result<List<Trip>>> response = Future.value(Ok([_trip]));
  @override
  Future<Result<List<Trip>>> trips(String coupleId) => response;
}

class _Photos extends Fake implements PhotoRepository {
  Future<Result<List<PhotoRecord>>> response = Future.value(
    Ok([
      PhotoRecord(
        id: 'photo-a',
        tripId: 'trip-a',
        regionId: '32060',
        objectKey: 'couple-a/trip-a/photo-a.jpg',
        uploadedBy: 'a',
        takenAt: DateTime(2026, 10, 1),
        width: 100,
        height: 100,
      ),
    ]),
  );
  @override
  Future<Result<List<PhotoRecord>>> forCouple(String coupleId) => response;
}

class _Sync extends Fake implements ScanSync {
  final calls = <CoupleScope>[];
  @override
  Future<Result<void>> sync(
    ScanSnapshot snapshot,
    DateTime startedOn, {
    required String userId,
    required String coupleId,
  }) async {
    calls.add((userId: userId, coupleId: coupleId));
    return const Ok(null);
  }
}

class _Fixture {
  final trips = _Trips();
  final photos = _Photos();
  Future<Couple?> couple = Future.value(
    const Couple(id: 'couple-a', partnerId: 'p'),
  );
  Future<Set<String>> home = Future.value({'32010'});
  Future<List<UserIdentity>> identities = FakeAuthRepository()
      .identities()
      .then((r) => r.valueOrThrow);
  Future<DateTime?> deletion = Future.value(DateTime(2026, 12, 1));

  late final container = ProviderContainer(
    retry: (count, error) => null,
    overrides: [
      sessionUserIdProvider.overrideWith((ref) => ref.watch(_user)),
      currentCoupleProvider.overrideWith((ref) {
        ref.watch(sessionUserIdProvider);
        return couple;
      }),
      tripRepositoryProvider.overrideWithValue(trips),
      photoRepositoryProvider.overrideWithValue(photos),
      homeRegionIdsProvider.overrideWith((ref) {
        ref.watch(sessionUserIdProvider);
        return home;
      }),
      regionNamesProvider.overrideWith((ref) async => {'32060': '속초시'}),
      provinceMapAssetProvider.overrideWith(
        (ref) => MapAsset.parse(
          File('assets/map/provinces_v1.json').readAsStringSync(),
        ),
      ),
      regionMapAssetProvider.overrideWith(
        (ref) => MapAsset.parse(
          File('assets/map/regions_v1.json').readAsStringSync(),
        ),
      ),
      realtimeSyncProvider.overrideWith((ref) {}),
      tripCandidatesProvider.overrideWith((ref) async => []),
      signedUrlCacheProvider.overrideWithValue(
        SignedUrlCache((paths) async => {}),
      ),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      identitiesProvider('a').overrideWith((ref) => identities),
      myDeletionDateProvider('a').overrideWith((ref) => deletion),
      partnerDeletionDatesProvider(
        'a',
      ).overrideWith((ref) async => [DateTime(2026, 12, 2)]),
    ],
  );

  Future<void> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: page),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }
}

void main() {
  for (final accountChange in [true, false]) {
    test('스캔 대기 중 ${accountChange ? '계정' : '커플'}이 바뀌면 이전 범위로 쓰지 않는다', () async {
      final pending = Completer<ScanSnapshot>();
      final nextCouple = Completer<Couple?>();
      final sync = _Sync();
      Future<Couple?> couple = Future.value(
        Couple(id: 'couple-a', partnerId: 'p', startedOn: DateTime(2026)),
      );
      final container = ProviderContainer(
        retry: (count, error) => null,
        overrides: [
          sessionUserIdProvider.overrideWith((ref) => ref.watch(_user)),
          currentCoupleProvider.overrideWith((ref) {
            ref.watch(sessionUserIdProvider);
            return couple;
          }),
          scanSnapshotProvider.overrideWith((ref) => pending.future),
          scanSyncProvider.overrideWithValue(sync),
        ],
      );
      final subscription = container.listen(photoDaysSyncedProvider, (_, _) {});
      await container.pump();
      couple = nextCouple.future;
      if (accountChange) {
        container.read(_user.notifier).set('b');
      } else {
        container.invalidate(currentCoupleProvider);
      }
      pending.complete(ScanSnapshot({}, DateTime(2026, 11, 18)));
      await container.pump();
      expect(sync.calls, isEmpty);
      nextCouple.complete(
        Couple(id: 'couple-b', partnerId: 'q', startedOn: DateTime(2026)),
      );
      await container.read(photoDaysSyncedProvider.future);
      await container.pump();
      expect(sync.calls, [
        (userId: accountChange ? 'b' : 'a', coupleId: 'couple-b'),
      ]);
      subscription.close();
      container.dispose();
    });
  }

  for (final national in [true, false]) {
    testWidgets('${national ? '전국' : '시도'} 지도는 재조회와 오프라인 오류에 마지막 진행률을 유지한다', (
      tester,
    ) async {
      final f = _Fixture();
      await f.pump(
        tester,
        national
            ? const NationalMapPage()
            : const ProvinceMapPage(provinceId: '32'),
      );
      final before = tester.widget<PuzzleMap>(find.byType(PuzzleMap));
      expect(before.visitedRegionIds, contains(national ? '32' : '32060'));
      final pending = Completer<Result<List<Trip>>>();
      final home = Completer<Set<String>>();
      f.trips.response = pending.future;
      f.home = home.future;
      f.container.invalidate(tripsProvider);
      f.container.invalidate(homeRegionIdsProvider);
      await tester.pump();
      final refreshing = tester.widget<PuzzleMap>(find.byType(PuzzleMap));
      expect(refreshing.visitedRegionIds, before.visitedRegionIds);
      expect(refreshing.homeRegionIds, before.homeRegionIds);
      pending.complete(const Err(AppError.network));
      home.completeError(AppError.network);
      await tester.pumpAndSettle();
      final offline = tester.widget<PuzzleMap>(find.byType(PuzzleMap));
      expect(offline.visitedRegionIds, before.visitedRegionIds);
      expect(offline.homeRegionIds, before.homeRegionIds);
      await f.close(tester);
    });
  }

  testWidgets('앨범은 여행과 사진을 재조회하는 동안 기존 여행과 사진 수를 유지한다', (tester) async {
    final f = _Fixture();
    await f.pump(tester, const AlbumPage());
    expect(find.text('이전 여행'), findsOneWidget);
    expect(find.textContaining('사진 1장'), findsOneWidget);
    final trips = Completer<Result<List<Trip>>>();
    final photos = Completer<Result<List<PhotoRecord>>>();
    f.trips.response = trips.future;
    f.photos.response = photos.future;
    f.container.invalidate(tripsProvider);
    f.container.invalidate(couplePhotosProvider);
    await tester.pump();
    expect(find.text('이전 여행'), findsOneWidget);
    expect(find.textContaining('사진 1장'), findsOneWidget);
    trips.complete(const Err(AppError.network));
    photos.complete(const Err(AppError.network));
    await tester.pumpAndSettle();
    expect(find.text('이전 여행'), findsOneWidget);
    expect(find.textContaining('사진 1장'), findsOneWidget);
    await f.close(tester);
  });

  testWidgets('계정 연결과 삭제 배너는 같은 계정의 재조회 중 기존 값을 유지한다', (tester) async {
    final f = _Fixture();
    await f.pump(
      tester,
      const Column(
        children: [
          Expanded(child: AccountLinksPage()),
          DeletionBanners(),
        ],
      ),
    );
    expect(find.text('카카오'), findsOneWidget);
    expect(find.text('12월 1일에 계정이 삭제돼요'), findsOneWidget);
    final identities = Completer<List<UserIdentity>>();
    final deletion = Completer<DateTime?>();
    f.identities = identities.future;
    f.deletion = deletion.future;
    f.container.invalidate(identitiesProvider('a'));
    f.container.invalidate(myDeletionDateProvider('a'));
    await tester.pump();
    expect(find.text('카카오'), findsOneWidget);
    expect(find.text('12월 1일에 계정이 삭제돼요'), findsOneWidget);
    identities.completeError(AppError.network);
    deletion.completeError(AppError.network);
    await tester.pumpAndSettle();
    expect(find.text('카카오'), findsOneWidget);
    expect(find.text('12월 1일에 계정이 삭제돼요'), findsOneWidget);
    await f.close(tester);
  });

  testWidgets('같은 계정의 커플이 바뀌면 새 응답 전 이전 여행과 사진이 보이지 않는다', (tester) async {
    final f = _Fixture();
    await f.pump(tester, const AlbumPage());
    expect(find.text('이전 여행'), findsOneWidget);
    final trips = Completer<Result<List<Trip>>>();
    final photos = Completer<Result<List<PhotoRecord>>>();
    f.trips.response = trips.future;
    f.photos.response = photos.future;
    f.couple = Future.value(const Couple(id: 'couple-b', partnerId: 'q'));
    f.container.invalidate(currentCoupleProvider);
    await tester.pump();
    await tester.pump();
    expect(find.text('이전 여행'), findsNothing);
    expect(find.textContaining('사진 1장'), findsNothing);
    trips.complete(const Ok([]));
    photos.complete(const Ok([]));
    await tester.pumpAndSettle();
    await f.close(tester);
  });

  test('이전 계정의 대기 중 커플 응답은 새 계정 범위가 되지 않는다', () async {
    final pendingA = Completer<Couple?>();
    final pendingB = Completer<Couple?>();
    final f = _Fixture()..couple = pendingA.future;
    final subscription = f.container.listen(
      scopedCurrentCoupleProvider,
      (_, _) {},
    );
    f.couple = pendingB.future;
    f.container.read(_user.notifier).set('b');
    expect(f.container.read(currentCoupleScopeProvider), isNull);
    pendingA.complete(const Couple(id: 'couple-a', partnerId: 'p'));
    await f.container.pump();
    expect(f.container.read(currentCoupleScopeProvider), isNull);
    pendingB.complete(const Couple(id: 'couple-b', partnerId: 'q'));
    await f.container.read(currentCoupleForUserProvider('b').future);
    await f.container.pump();
    expect(f.container.read(currentCoupleScopeProvider), (
      userId: 'b',
      coupleId: 'couple-b',
    ));
    subscription.close();
    f.container.dispose();
  });

  for (final nextUser in ['b', null]) {
    testWidgets('계정이 $nextUser 로 바뀌면 커플 응답 전에도 이전 지도와 앨범을 숨긴다', (tester) async {
      final f = _Fixture();
      await f.pump(
        tester,
        const Column(
          children: [
            Expanded(child: ProvinceMapPage(provinceId: '32')),
            Expanded(child: AlbumPage()),
          ],
        ),
      );
      expect(find.text('이전 여행'), findsOneWidget);
      final couple = Completer<Couple?>();
      f.couple = couple.future;
      f.trips.response = Future.value(const Ok([]));
      f.photos.response = Future.value(const Ok([]));
      f.home = Future.value({});
      f.container.read(_user.notifier).set(nextUser);
      await tester.pump();
      final map = tester.widget<PuzzleMap>(find.byType(PuzzleMap));
      expect(map.visitedRegionIds, isEmpty);
      expect(map.homeRegionIds, isEmpty);
      expect(find.text('이전 여행'), findsNothing);
      couple.complete(
        nextUser == null ? null : const Couple(id: 'couple-b', partnerId: 'p'),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('이전 여행'), findsNothing);
      await f.close(tester);
    });
  }
}
