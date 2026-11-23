import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/photo_library_repository.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/rescan.dart';
import 'package:woori_piece/features/scan/scan_store.dart';
import 'package:woori_piece/features/scan/scanner.dart';
import 'package:woori_piece/map_data/geo_region_locator.dart';
import 'package:woori_piece/map_data/map_asset.dart';

class FakePhotoLibrary extends PhotoLibraryRepository {
  FakePhotoLibrary(this.result);

  final Result<PhotoScan> result;
  final sinceValues = <DateTime?>[];

  @override
  Future<Result<PhotoScan>> readLocatedPhotos({
    DateTime? since,
    DateTime? until,
  }) async {
    sinceValues.add(since);
    return result;
  }
}

void main() {
  final locator = GeoRegionLocator(
    MapAsset.parse(File('assets/map/regions_v1.json').readAsStringSync()),
  );
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('rescan');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('전체 스캔 성공 뒤에만 화면의 스캔 결과를 갱신한다', () async {
    final library = FakePhotoLibrary(
      const Ok((total: 0, located: <PhotoMeta>[])),
    );
    var refreshed = false;
    final result = await rescan(
      Scanner(library, locator, ScanStore(directory, userId: 'user-a')),
      () => refreshed = true,
    );

    expect(result, isA<Ok<void>>());
    expect(library.sinceValues, [null]);
    expect(refreshed, isTrue);
  });

  test('스캔 실패 시 기존 결과 갱신을 요청하지 않는다', () async {
    final library = FakePhotoLibrary(const Err(AppError.photoPermission));
    var refreshed = false;
    final result = await rescan(
      Scanner(library, locator, ScanStore(directory, userId: 'user-a')),
      () => refreshed = true,
    );

    expect(result, isA<Err<void>>());
    expect(library.sinceValues, [null]);
    expect(refreshed, isFalse);
  });
}
