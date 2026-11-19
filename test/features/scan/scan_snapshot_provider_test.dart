import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/photo_library_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/auth/account_state.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/scan_store.dart';
import 'package:woori_piece/map_data/geo_region_locator.dart';
import 'package:woori_piece/map_data/map_asset.dart';

class _Library extends PhotoLibraryRepository {
  var reads = 0;

  @override
  Future<Result<PhotoScan>> readLocatedPhotos({DateTime? since}) async {
    reads++;
    return const Ok((total: 0, located: <PhotoMeta>[]));
  }
}

void main() {
  test('삭제 일정을 다시 읽어도 값이 같으면 사진첩을 다시 스캔하지 않는다', () async {
    final dir = Directory.systemTemp.createTempSync('snapshot');
    addTearDown(() => dir.deleteSync(recursive: true));
    final library = _Library();
    DateTime? deletion;
    final container = ProviderContainer(
      overrides: [
        sessionUserIdProvider.overrideWithValue('user-a'),
        myDeletionDateProvider.overrideWith((ref, _) async => deletion),
        scanStoreProvider.overrideWith(
          (ref, userId) => ScanStore(dir, userId: userId),
        ),
        photoLibraryRepositoryProvider.overrideWithValue(library),
        regionLocatorProvider.overrideWith(
          (ref) => GeoRegionLocator(
            MapAsset.parse(
              File('assets/map/regions_v1.json').readAsStringSync(),
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(scanSnapshotProvider('user-a'), (_, _) {});

    await container.read(scanSnapshotProvider('user-a').future);
    expect(library.reads, 1);

    container.invalidate(myDeletionDateProvider('user-a'));
    await container.read(myDeletionDateProvider('user-a').future);
    await container.read(scanSnapshotProvider('user-a').future);
    expect(library.reads, 1);

    deletion = DateTime(2026, 12, 20);
    container.invalidate(myDeletionDateProvider('user-a'));
    await container.read(myDeletionDateProvider('user-a').future);
    expect(
      await container.read(scanSnapshotProvider('user-a').future),
      ScanSnapshot.empty,
    );
    expect(library.reads, 1);
  });
}
