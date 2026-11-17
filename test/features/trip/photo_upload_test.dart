import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'package:woori_piece/features/trip/photo_selection.dart';
import 'package:woori_piece/features/trip/photo_upload_page.dart';

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

void main() {
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

  Future<FakePhotoRepository> pump(WidgetTester tester) async {
    final repo = FakePhotoRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripLocalPhotosProvider(query).overrideWith((ref) async => photos),
          photoRepositoryProvider.overrideWithValue(repo),
          originalBytesProvider.overrideWithValue((_) async => Uint8List(1)),
        ],
        child: MaterialApp(home: PhotoUploadPage(query: query)),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('여행 조각의 사진만 기본 6장 선택되고 다른 조각·위치 없는 사진은 빠진다', (tester) async {
    await pump(tester);
    expect(find.text('6장 올리기'), findsOneWidget);
  });

  testWidgets('올리면 고른 사진마다 조각과 촬영 시각으로 업로드한다', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.text('6장 올리기'));
    await tester.pumpAndSettle();
    expect(repo.calls, hasLength(6));
    expect(
      repo.calls.every((c) => c.tripId == 't1' && c.regionId == '32060'),
      isTrue,
    );
    expect(repo.calls.first.takenAt, DateTime(2026, 10, 3, 0));
  });

  testWidgets('사진첩에서 더 고른 사진을 함께 올린다', (tester) async {
    final repo = FakePhotoRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tripLocalPhotosProvider(query).overrideWith((ref) async => const []),
          photoRepositoryProvider.overrideWithValue(repo),
          originalBytesProvider.overrideWithValue((_) async => Uint8List(1)),
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
          tripLocalPhotosProvider(query).overrideWith((ref) async => photos),
          photoRepositoryProvider.overrideWithValue(repo),
          originalBytesProvider.overrideWithValue((_) async => Uint8List(1)),
        ],
        child: MaterialApp(home: PhotoUploadPage(query: query)),
      ),
    );
    await tester.pumpAndSettle();
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
          tripLocalPhotosProvider(query).overrideWith((ref) async => photos),
          photoRepositoryProvider.overrideWithValue(repo),
          originalBytesProvider.overrideWithValue((id) async {
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
    await tester.tap(find.text('6장 올리기'));
    await tester.pumpAndSettle();
    expect(repo.calls.map((c) => c.asset), [0x31, 0x33, 0x34, 0x36, 0x37]);
    expect(find.text('2장 다시 올리기'), findsOneWidget);

    Future<void> tapPhoto(String id) async {
      final thumbnail = find.byWidgetPredicate(
        (widget) => widget is LocalThumbnail && widget.assetId == id,
      );
      await tester.tap(
        find
            .ancestor(of: thumbnail, matching: find.byType(GestureDetector))
            .first,
      );
    }

    await tapPhoto('s0');
    await tapPhoto('s2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('2장 다시 올리기'));
    await tester.pumpAndSettle();
    expect(repo.calls.map((c) => c.asset), [
      0x31,
      0x33,
      0x34,
      0x36,
      0x37,
      0x31,
      0x32,
    ]);
    expect(repo.calls[0].id, isNotNull);
    expect(repo.calls[0].id, repo.calls[5].id);
  });
}
