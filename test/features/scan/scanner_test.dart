import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/photo_library_repository.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/scan_store.dart';
import 'package:woori_piece/features/scan/scanner.dart';
import 'package:woori_piece/map_data/geo_region_locator.dart';
import 'package:woori_piece/map_data/map_asset.dart';

// 스캔이 쓰는 메서드만 흉내 낸다
class FakeLibrary extends PhotoLibraryRepository {
  FakeLibrary(this.result);

  final Result<PhotoScan> result;
  final sinceCalls = <DateTime?>[];

  @override
  Future<Result<PhotoScan>> readLocatedPhotos({DateTime? since}) async {
    sinceCalls.add(since);
    return result;
  }
}

void main() {
  final locator = GeoRegionLocator(
    MapAsset.parse(File('assets/map/regions_v1.json').readAsStringSync()),
  );
  late Directory dir;
  late ScanStore store;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('scanner');
    store = ScanStore(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final sokchoPhoto = PhotoMeta(
    DateTime(2026, 10, 3, 9),
    const GeoPoint(128.58, 38.19),
  );
  final sokcho = PhotoDay(DateTime(2026, 10, 3), '32060');

  test('증분 스캔은 마지막 스캔 시각 이후만 읽고 결과를 더한다', () async {
    await store.write(ScanSnapshot({sokcho: 2}, DateTime(2026, 11, 1)));
    final library = FakeLibrary(Ok((total: 1, located: [sokchoPhoto])));
    final result = await Scanner(library, locator, store).scan();
    expect(library.sinceCalls, [DateTime(2026, 11, 1)]);
    expect(result.valueOrThrow.days, {sokcho: 3});
    expect((await store.read()).days, {sokcho: 3});
  });

  test('다시 스캔은 처음부터 읽어 결과를 바꾼다', () async {
    await store.write(ScanSnapshot({sokcho: 9}, DateTime(2026, 11, 1)));
    final library = FakeLibrary(Ok((total: 1, located: [sokchoPhoto])));
    await Scanner(library, locator, store).scan(full: true);
    expect(library.sinceCalls, [null]);
    expect((await store.read()).days, {sokcho: 1});
  });

  test('권한이 없으면 오류를 돌려주고 저장 결과를 건드리지 않는다', () async {
    await store.write(ScanSnapshot({sokcho: 2}, DateTime(2026, 11, 1)));
    final library = FakeLibrary(const Err(AppError.photoPermission));
    final result = await Scanner(library, locator, store).scan();
    expect(
      result,
      isA<Err<ScanSnapshot>>().having(
        (e) => e.error,
        'error',
        AppError.photoPermission,
      ),
    );
    expect((await store.read()).days, {sokcho: 2});
  });
}
