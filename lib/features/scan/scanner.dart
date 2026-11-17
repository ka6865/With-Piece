import '../../core/result/result.dart';
import '../../data/repositories/photo_library_repository.dart';
import '../../map_data/geo_region_locator.dart';
import 'photo_days.dart';
import 'scan_store.dart';

// 사진첩을 읽어 (날짜, 조각) 결과를 기기 안 파일에 쌓는다(설계 5.1)
class Scanner {
  Scanner(this.library, this.locator, this.store);

  final PhotoLibraryRepository library;
  final GeoRegionLocator locator;
  final ScanStore store;

  // shortcut: 증분은 촬영(생성) 시각 기준이라 나중에 들여온 옛 사진은 놓친다.
  // 설정의 "다시 스캔"(full)이 메운다
  Future<Result<ScanSnapshot>> scan({bool full = false}) async {
    final previous = full ? ScanSnapshot.empty : await store.read();
    final startedAt = DateTime.now();
    final result = await library.readLocatedPhotos(since: previous.scannedAt);
    switch (result) {
      case Err(:final error):
        return Err(error);
      case Ok(:final value):
        final days = aggregatePhotoDays(value.located, locator);
        final next = full
            ? ScanSnapshot(days, startedAt)
            : previous.merge(days, startedAt);
        await store.write(next);
        return Ok(next);
    }
  }
}
