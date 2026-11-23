import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/album/album_providers.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/map/region_covers.dart';
import 'package:woori_piece/features/map/painter/puzzle_layout.dart';
import 'package:woori_piece/features/map/view/province_map_page.dart';
import 'package:woori_piece/features/map/view/puzzle_map.dart';
import 'package:woori_piece/features/scan/home_regions.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/map_data/map_asset.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';

import '../../trip/fakes.dart';

final provinces = MapAsset.parse(
  File('assets/map/provinces_v1.json').readAsStringSync(),
);
final regions = MapAsset.parse(
  File('assets/map/regions_v1.json').readAsStringSync(),
);

class OverrideRecorder extends FakeTripRepository {
  final calls = <(String, String, OverrideKind?)>[];

  @override
  Future<Result<void>> setOverride(
    String coupleId,
    String regionId,
    OverrideKind? kind,
  ) async {
    calls.add((coupleId, regionId, kind));
    return const Ok(null);
  }
}

void main() {
  testWidgets('생활권 조각은 접근성 레이블에 생활권이 붙는다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: PuzzleMap(
          asset: regions,
          visitedRegionIds: const {},
          homeRegionIds: const {'32060'},
          onRegionTap: (_) {},
        ),
      ),
    );
    // CustomPainter의 시맨틱 노드는 위젯이 아니어서 시맨틱 트리에서 찾는다
    expect(find.semantics.byLabel('속초시, 생활권'), findsOne);
    semantics.dispose();
  });

  testWidgets('생활권 조각을 길게 눌러 여행지로 바꾼다', (tester) async {
    final trips = OverrideRecorder();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          provinceMapAssetProvider.overrideWith((ref) => provinces),
          regionMapAssetProvider.overrideWith((ref) => regions),
          tripRepositoryProvider.overrideWithValue(trips),
          tripsProvider.overrideWith((ref) async => const []),
          homeRegionIdsProvider.overrideWith((ref) async => {'32060'}),
          currentCoupleProvider.overrideWith(
            (ref) async => const Couple(id: 'c1', partnerId: 'p'),
          ),
        ],
        child: const MaterialApp(home: ProvinceMapPage(provinceId: '32')),
      ),
    );
    await tester.pumpAndSettle();
    final box = tester.renderObject<RenderBox>(find.byType(PuzzleMap));
    final layout = PuzzleLayout.build(
      asset: provinceAssetOf(regions, '32')!,
      size: box.size,
    );
    await tester.longPressAt(box.localToGlobal(layout.labelPoints['32060']!));
    await tester.pumpAndSettle();
    await tester.tap(find.text('여행지로 바꾸기'));
    await tester.pumpAndSettle();
    expect(trips.calls.single, ('c1', '32060', OverrideKind.travel));
  });

  testWidgets('대표 사진 원본을 받는 동안 썸네일로 먼저 채운다', (tester) async {
    final photo = PhotoRecord(
      id: 'p1',
      tripId: 't1',
      regionId: '32060',
      objectKey: 'c1/t1/p1.heic',
      uploadedBy: 'me',
      takenAt: DateTime(2026, 10, 3),
      width: 2048,
      height: 1536,
    );
    final thumb = await tester.runAsync(
      () => createTestImage(width: 4, height: 4),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          provinceMapAssetProvider.overrideWith((ref) => provinces),
          regionMapAssetProvider.overrideWith((ref) => regions),
          tripsProvider.overrideWith((ref) async => const []),
          homeRegionIdsProvider.overrideWith((ref) async => {'32060'}),
          currentCoupleProvider.overrideWith(
            (ref) async => const Couple(id: 'c1', partnerId: 'p'),
          ),
          couplePhotosProvider('me').overrideWith((ref) async => [photo]),
          regionCoversProvider.overrideWith((ref) async => const {}),
          // 원본은 끝나지 않는다
          coverImageProvider(
            photo.fullPath,
          ).overrideWith((ref) => Completer<Never>().future),
          coverImageProvider(
            photo.thumbPath,
          ).overrideWith((ref) async => thumb!.clone()),
        ],
        child: const MaterialApp(home: ProvinceMapPage(provinceId: '32')),
      ),
    );
    await tester.pumpAndSettle();
    final map = tester.widget<PuzzleMap>(find.byType(PuzzleMap));
    expect(map.covers.keys, ['32060']);
    thumb!.dispose();
  });
}
