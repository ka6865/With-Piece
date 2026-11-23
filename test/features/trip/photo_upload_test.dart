import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/trip/local_photo_viewer.dart';
import 'package:woori_piece/features/trip/photo_selection.dart';
import 'package:woori_piece/features/trip/photo_upload_page.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';

import 'fakes.dart';

class UploadCall {
  UploadCall(this.asset, this.tripId, this.regionId, this.takenAt, this.id);

  final int asset;
  final String tripId;
  final String? regionId;
  final DateTime? takenAt;
  final String? id;
}

class FakePhotoRepository implements PhotoRepository {
  final calls = <UploadCall>[];
  final failFirst = <int>{};
  final failAlways = <int>{};
  var currentUsage = const PhotoUsage(0, 1000);

  @override
  Future<Result<PhotoUsage>> usage(String coupleId) async => Ok(currentUsage);

  @override
  Future<Result<List<PhotoRecord>>> forCouple(String coupleId) async =>
      const Ok([]);

  @override
  Future<Result<void>> delete(PhotoRecord photo) async => const Ok(null);

  @override
  Future<Result<String>> upload({
    required String coupleId,
    required String tripId,
    required String? regionId,
    required DateTime? takenAt,
    required Uint8List original,
    String? id,
  }) async {
    final asset = original.single;
    calls.add(UploadCall(asset, tripId, regionId, takenAt, id));
    if (failAlways.contains(asset) || failFirst.remove(asset)) {
      return const Err(AppError.unknown);
    }
    return Ok('photo-${calls.length}');
  }
}

// 사진 격자의 칸 수 기억(PinchColumns)이 읽는다
late SharedPreferences testPrefs;

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testPrefs = await SharedPreferences.getInstance();
  });

  final photos = [
    for (var h = 0; h < 8; h++)
      LocalPhoto(
        assetId: 's$h',
        takenAt: DateTime(2026, 10, 3, h),
        regionId: '32060',
      ),
    LocalPhoto(
      assetId: 'none',
      takenAt: DateTime(2026, 10, 3, 12),
      regionId: null,
    ),
  ];
  final query = TripPhotoQuery(
    coupleId: 'c1',
    tripId: 't1',
    range: DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 3)),
    regionIds: const {'32060'},
  );

  Future<void> tapPhoto(WidgetTester tester, String id) async {
    final thumbnail = find.byWidgetPredicate(
      (widget) => widget is LocalThumbnail && widget.assetId == id,
    );
    await tester.tap(
      find
          .ancestor(of: thumbnail, matching: find.byType(GestureDetector))
          .first,
    );
    await tester.pump();
  }

  // 예전 기본 선택과 같은 6장
  const six = ['s0', 's1', 's3', 's4', 's6', 's7'];
  Future<void> selectSix(WidgetTester tester) async {
    for (final id in six) {
      await tapPhoto(tester, id);
    }
  }

  Future<FakePhotoRepository> pump(WidgetTester tester) async {
    final repo = FakePhotoRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(testPrefs),
          sessionUserIdProvider.overrideWithValue(null),
          tripLocalPhotosProvider(query).overrideWith((ref) async => photos),
          photoRepositoryProvider.overrideWithValue(repo),
          originalBytesProvider.overrideWithValue((_, _) async => Uint8List(1)),
        ],
        child: MaterialApp(home: PhotoUploadPage(query: query)),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('한국 시간 사귄 날부터 고를 수 있고 남은 업로드 한도를 알려 준다', (tester) async {
    final cutoff = DateTime.utc(2026, 10, 2, 15);
    final repo = FakePhotoRepository()
      ..currentUsage = const PhotoUsage(999, 1000);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(testPrefs),
          sessionUserIdProvider.overrideWithValue(null),
          scopedCurrentCoupleProvider.overrideWithValue(
            AsyncData(
              Couple(
                id: 'c1',
                partnerId: 'p',
                startedOn: DateTime(2026, 10, 3),
              ),
            ),
          ),
          tripLocalPhotosProvider(query).overrideWith(
            (ref) async => [
              LocalPhoto(
                assetId: 'before',
                takenAt: cutoff.subtract(const Duration(milliseconds: 1)),
                regionId: null,
              ),
              LocalPhoto(assetId: 'boundary', takenAt: cutoff, regionId: null),
            ],
          ),
          photoRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(home: PhotoUploadPage(query: query)),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is LocalThumbnail && w.assetId == 'before',
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is LocalThumbnail && w.assetId == 'boundary',
      ),
      findsOneWidget,
    );
    expect(find.text('커플 사진을 1장 더 올릴 수 있어요'), findsOneWidget);
  });

  testWidgets('미리 골라 두지 않고 직접 고른 사진만 올린다', (tester) async {
    await pump(tester);
    expect(find.text('0장 올리기'), findsOneWidget);
    await tapPhoto(tester, 's0');
    await tapPhoto(tester, 's1');
    expect(find.text('2장 올리기'), findsOneWidget);
  });

  testWidgets('옆으로 끌면 끈 범위를 한꺼번에 고르고, 고른 데서 시작하면 뺀다', (tester) async {
    await pump(tester);
    Offset center(String id) => tester.getCenter(
      find.byWidgetPredicate((w) => w is LocalThumbnail && w.assetId == id),
    );
    // 첫 줄 s0에서 둘째 줄 s5까지
    final gesture = await tester.startGesture(center('s0'));
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveTo(center('s5'));
    await gesture.up();
    await tester.pump();
    expect(find.text('6장 올리기'), findsOneWidget);
    final back = await tester.startGesture(center('s1'));
    await back.moveBy(const Offset(30, 0));
    await back.moveTo(center('s2'));
    await back.up();
    await tester.pump();
    expect(find.text('4장 올리기'), findsOneWidget);
  });

  testWidgets('길게 누르면 크게 보고, 넘겨서 그 화면에서 고른다', (tester) async {
    final loader = LocalPhotoViewerPage.loader;
    LocalPhotoViewerPage.loader = (_) async => null;
    addTearDown(() => LocalPhotoViewerPage.loader = loader);
    await pump(tester);
    await tester.longPress(
      find.byWidgetPredicate((w) => w is LocalThumbnail && w.assetId == 's2'),
    );
    await tester.pumpAndSettle();
    expect(find.text('3 / 9'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsWidgets);
    // 크게 보기만 해서는 고르지 않는다
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text('4 / 9'), findsOneWidget);
    await tester.tap(find.byTooltip('고르기'));
    await tester.pump();
    expect(find.byTooltip('고르기 해제'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('1장 올리기'), findsOneWidget);
  });

  testWidgets('올리면 고른 사진마다 조각과 촬영 시각으로 업로드한다', (tester) async {
    final repo = await pump(tester);
    await selectSix(tester);
    await tester.tap(find.text('6장 올리기'));
    await tester.pumpAndSettle();
    expect(repo.calls, hasLength(6));
    expect(
      repo.calls.every((c) => c.tripId == 't1' && c.regionId == '32060'),
      isTrue,
    );
    expect(
      repo.calls.map((c) => c.takenAt),
      contains(DateTime(2026, 10, 3, 0)),
    );
  });

  testWidgets('사진첩에서 더 고른 사진을 함께 올린다', (tester) async {
    final repo = FakePhotoRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(testPrefs),
          sessionUserIdProvider.overrideWithValue(null),
          tripLocalPhotosProvider(query).overrideWith((ref) async => const []),
          photoRepositoryProvider.overrideWithValue(repo),
          originalBytesProvider.overrideWithValue((_, _) async => Uint8List(1)),
          libraryPickerProvider.overrideWithValue(
            (context) async => [
              LocalPhoto(
                assetId: 'x',
                takenAt: DateTime(2026, 9, 1),
                regionId: null,
              ),
            ],
          ),
        ],
        child: MaterialApp(home: PhotoUploadPage(query: query)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('사진첩에서 더 고르기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1장 올리기'));
    await tester.pumpAndSettle();
    expect(repo.calls.single.takenAt, DateTime(2026, 9, 1));
  });

  testWidgets('모두 실패하면 선택을 남기고 화면을 유지한다', (tester) async {
    final repo = FakePhotoRepository()..failAlways.add(0);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(testPrefs),
          sessionUserIdProvider.overrideWithValue(null),
          tripLocalPhotosProvider(query).overrideWith((ref) async => photos),
          photoRepositoryProvider.overrideWithValue(repo),
          originalBytesProvider.overrideWithValue((_, _) async => Uint8List(1)),
        ],
        child: MaterialApp(home: PhotoUploadPage(query: query)),
      ),
    );
    await tester.pumpAndSettle();
    await selectSix(tester);
    await tester.tap(find.text('6장 올리기'));
    await tester.pumpAndSettle();
    expect(find.text('사진 고르기'), findsOneWidget);
    expect(find.text('6장 다시 올리기'), findsOneWidget);
  });

  testWidgets('재시도는 현재 선택한 실패 사진과 새 선택만 올린다', (tester) async {
    final repo = FakePhotoRepository()..failFirst.addAll([0x73, 0x31]);
    var originalReadFailed = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(testPrefs),
          sessionUserIdProvider.overrideWithValue(null),
          tripLocalPhotosProvider(query).overrideWith((ref) async => photos),
          photoRepositoryProvider.overrideWithValue(repo),
          originalBytesProvider.overrideWithValue((id, _) async {
            if (id == 's0' && originalReadFailed) {
              originalReadFailed = false;
              throw StateError('원본을 읽지 못함');
            }
            return Uint8List.fromList([id.codeUnitAt(1)]);
          }),
        ],
        child: MaterialApp(home: PhotoUploadPage(query: query)),
      ),
    );
    await tester.pumpAndSettle();
    await selectSix(tester);
    await tester.tap(find.text('6장 올리기'));
    await tester.pumpAndSettle();
    // 동시에 올려 순서는 정해지지 않는다
    expect(repo.calls.map((c) => c.asset).toSet(), {
      0x31,
      0x33,
      0x34,
      0x36,
      0x37,
    });
    expect(find.text('2장 다시 올리기'), findsOneWidget);

    await tapPhoto(tester, 's0');
    await tapPhoto(tester, 's2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('2장 다시 올리기'));
    await tester.pumpAndSettle();
    expect(repo.calls.skip(5).map((c) => c.asset).toSet(), {0x31, 0x32});
    // 다시 올린 사진은 처음과 같은 id로 올려 중복 행을 만들지 않는다
    final s1Ids = {
      for (final c in repo.calls)
        if (c.asset == 0x31) c.id,
    };
    expect(s1Ids, hasLength(1));
    expect(s1Ids.single, isNotNull);
  });

  testWidgets('원본을 받는 중 중단하면 미완료 선택을 남긴다', (tester) async {
    final repo = FakePhotoRepository();
    var reads = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(testPrefs),
          sessionUserIdProvider.overrideWithValue(null),
          tripLocalPhotosProvider(query).overrideWith((ref) async => photos),
          photoRepositoryProvider.overrideWithValue(repo),
          prefetchOriginalProvider.overrideWithValue((_, _) async {}),
          originalBytesProvider.overrideWithValue((_, _) {
            reads++;
            return Completer<Uint8List?>().future;
          }),
        ],
        child: MaterialApp(home: PhotoUploadPage(query: query)),
      ),
    );
    await tester.pumpAndSettle();
    await selectSix(tester);
    await tester.tap(find.text('6장 올리기'));
    await tester.pump();
    expect(reads, uploadWorkers);
    await tester.tap(find.text('중단'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    expect(reads, uploadWorkers);
    expect(find.text('6장 다시 올리기'), findsOneWidget);
  });

  testWidgets('화면을 다시 열어도 실패한 업로드는 저장한 ID를 재사용하고 오래된 ID는 지운다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pending_photo_upload:stale': 'old-id 0',
      'pending_photo_upload:5f5df66841e627be58b93c8fc20db1de7ef7c397a7195b451aed8d1000a088c2':
          '73557da8-1a24-4c7f-a866-2aca16571075',
      'other': 'kept',
    });
    final prefs = await SharedPreferences.getInstance();
    final repo = FakePhotoRepository()..failFirst.add(0);
    Future<void> open() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionUserIdProvider.overrideWithValue('u1'),
            currentCoupleProvider.overrideWith(
              (ref) async => const Couple(id: 'c1', partnerId: 'p'),
            ),
            sharedPreferencesProvider.overrideWithValue(prefs),
            tripLocalPhotosProvider(query).overrideWith((ref) async => photos),
            photoRepositoryProvider.overrideWithValue(repo),
            prefetchOriginalProvider.overrideWithValue((_, _) async {}),
            originalBytesProvider.overrideWithValue(
              (_, _) async => Uint8List(1),
            ),
          ],
          child: MaterialApp(home: PhotoUploadPage(query: query)),
        ),
      );
      await tester.pumpAndSettle();
      await tapPhoto(tester, 's0');
      await tester.tap(find.text('1장 올리기'));
      await tester.pumpAndSettle();
    }

    await open();
    final id = repo.calls.single.id;
    expect(id, '73557da8-1a24-4c7f-a866-2aca16571075');
    expect(prefs.getKeys(), hasLength(2));
    expect(prefs.getKeys(), isNot(contains('pending_photo_upload:stale')));
    await tester.pumpWidget(const SizedBox());
    await open();
    expect(repo.calls, hasLength(2));
    expect(repo.calls.last.id, id);
    expect(prefs.getKeys(), {'other'});
  });

  test('여행에 없는 조각의 사진과 바뀐 자동 제목을 찾는다', () {
    expect(
      regionsOutsideTrip(
        [
          LocalPhoto(assetId: 'a', takenAt: DateTime(2026), regionId: '32060'),
          LocalPhoto(assetId: 'b', takenAt: DateTime(2026), regionId: '32400'),
          LocalPhoto(assetId: 'c', takenAt: DateTime(2026), regionId: null),
        ],
        {'32060'},
      ),
      {'32400'},
    );
    const names = {'32060': '속초시', '32400': '고성군'};
    final auto = Trip(
      id: 't1',
      title: '속초시 1박 2일',
      range: DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 4)),
      status: TripStatus.confirmed,
      source: TripSource.auto,
      regionIds: const ['32060'],
    );
    expect(retitledTrip(auto, ['32400'], names), '속초시 고성군 1박 2일');
    final custom = Trip(
      id: 't1',
      title: '우리 첫 바다',
      range: auto.range,
      status: TripStatus.confirmed,
      source: TripSource.auto,
      regionIds: const ['32060'],
    );
    expect(retitledTrip(custom, ['32400'], names), isNull);
  });

  testWidgets('여행에 없는 조각에서 찍은 사진을 올리면 그 조각을 넣을지 묻는다', (tester) async {
    final repo = FakePhotoRepository();
    final trips = FakeTripRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(testPrefs),
          sessionUserIdProvider.overrideWithValue(null),
          tripLocalPhotosProvider(query).overrideWith(
            (ref) async => [
              LocalPhoto(
                assetId: 'g',
                takenAt: DateTime(2026, 10, 3, 9),
                regionId: '32400',
              ),
            ],
          ),
          photoRepositoryProvider.overrideWithValue(repo),
          tripRepositoryProvider.overrideWithValue(trips),
          originalBytesProvider.overrideWithValue((_, _) async => Uint8List(1)),
          regionNamesProvider.overrideWith(
            (ref) async => {'32060': '속초시', '32400': '고성군'},
          ),
          tripsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(home: PhotoUploadPage(query: query)),
      ),
    );
    await tester.pumpAndSettle();
    await tapPhoto(tester, 'g');
    await tester.tap(find.text('1장 올리기'));
    await tester.pumpAndSettle();
    expect(find.text('고성군에서 찍은 사진도 있어요. 이 여행에 고성군도 넣을까요?'), findsOneWidget);
    await tester.tap(find.text('넣기'));
    await tester.pumpAndSettle();
    expect(trips.added, ['32400']);
  });

  testWidgets('고르는 순간 원본을 미리 받고, 다시 골라도 한 번만 받는다', (tester) async {
    final prefetched = <String>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(testPrefs),
          sessionUserIdProvider.overrideWithValue(null),
          tripLocalPhotosProvider(query).overrideWith((ref) async => photos),
          photoRepositoryProvider.overrideWithValue(FakePhotoRepository()),
          originalBytesProvider.overrideWithValue((_, _) async => Uint8List(1)),
          prefetchOriginalProvider.overrideWithValue((id, _) async {
            prefetched.add(id);
          }),
        ],
        child: MaterialApp(home: PhotoUploadPage(query: query)),
      ),
    );
    await tester.pumpAndSettle();
    await tapPhoto(tester, 's0');
    await tapPhoto(tester, 's1');
    await tapPhoto(tester, 's0');
    await tapPhoto(tester, 's0');
    await tester.pumpAndSettle();
    expect(prefetched, ['s0', 's1']);
  });
}
