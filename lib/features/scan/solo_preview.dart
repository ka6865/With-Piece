import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../map_data/map_asset_loader.dart';
import '../map/view/puzzle_map.dart';
import 'scan_providers.dart';
import 'scan_store.dart';

// 혼자일 때 내 사진첩으로 칠한 지도를 흐리게 보여 초대를 유도한다(설계 5.6).
// 미리보기에는 기기 안의 스캔 결과만 쓴다
class SoloPreview extends ConsumerWidget {
  const SoloPreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(sessionUserIdProvider);
    final scan = userId == null
        ? const AsyncData<ScanSnapshot>(ScanSnapshot.empty)
        : ref.watch(scanSnapshotProvider(userId));
    final provinces = ref.watch(provinceMapAssetProvider).value;
    final regions = ref.watch(regionMapAssetProvider).value;
    if (scan.error == AppError.photoPermission) {
      return Column(
        children: [
          const Text('사진 전체 접근을 허용하면 내 사진으로 칠한 지도를 미리 볼 수 있어요'),
          TextButton(
            onPressed: PhotoManager.openSetting,
            child: const Text('설정 열기'),
          ),
        ],
      );
    }
    final snapshot = scan.unwrapPrevious().value;
    if (snapshot == null || provinces == null || regions == null) {
      return const SizedBox.shrink();
    }
    final regionIds = {for (final day in snapshot.days.keys) day.regionId};
    final provinceIds = {
      for (final id in regionIds) ?regions.byId(id)?.parentId,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: IgnorePointer(
              child: PuzzleMap(
                asset: provinces,
                visitedRegionIds: provinceIds,
                onRegionTap: (_) {},
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '내 사진으로 ${regionIds.length}조각을 찾았어요. '
          '연인이 들어오면 이 중 함께 간 곳이 맞춰져요.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
