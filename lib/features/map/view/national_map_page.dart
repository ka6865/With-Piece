import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../map_data/map_asset_loader.dart';
import '../../scan/progress.dart';
import '../../auth/auth_state.dart';
import '../../scan/realtime_sync.dart';
import '../../scan/scan_providers.dart';
import 'puzzle_map.dart';
import '../../guide/guide.dart';

class NationalMapPage extends ConsumerWidget {
  const NationalMapPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provinces = ref.watch(provinceMapAssetProvider);
    final regions = ref.watch(regionMapAssetProvider);
    ref.watch(realtimeSyncProvider);
    // 진행 데이터가 없거나 오류여도 지도는 그린다(설계 12장)
    final scope = ref.watch(currentCoupleScopeProvider);
    final trips = scope == null
        ? null
        : ref.watch(scopedTripsProvider(scope)).value;
    final home = scope == null
        ? null
        : ref.watch(scopedHomeRegionIdsProvider(scope)).value;
    final filled = filledRegionIds(trips ?? const [], home ?? const {});
    return Scaffold(
      appBar: AppBar(
        title: const Text('우리들의 조각'),
        actions: const [HelpButton(topic: HelpTopic.map)],
      ),
      body: switch ((provinces, regions)) {
        (
          AsyncData(value: final provinceAsset),
          AsyncData(value: final regionAsset),
        ) =>
          () {
            final totals = regionAsset.pieceCountByProvince();
            final visited = filledCountByProvince(filled, {
              for (final f in regionAsset.features) f.id: f.parentId!,
            });
            return Column(
              children: [
                // 바다가 화면 가장자리까지 이어지도록 여백 없이 둔다
                Expanded(
                  child: PuzzleMap(
                    asset: provinceAsset,
                    // 시도를 통째로 칠하지 않고 다녀온 조각만 칠한다. 탭은 시도 단위다
                    pieceAsset: regionAsset,
                    visitedRegionIds: filledRegionIds(
                      trips ?? const [],
                      const {},
                    ),
                    homeRegionIds: home ?? const {},
                    showSea: true,
                    onRegionTap: (provinceId) =>
                        context.push('/province/$provinceId'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  // 지도에 세로 공간을 더 주려고 진행률을 가로 한 줄로 둔다
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        for (final province in provinceAsset.features)
                          TextButton(
                            style: TextButton.styleFrom(
                              minimumSize: const Size(44, 44),
                            ),
                            onPressed: () =>
                                context.push('/province/${province.id}'),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  province.name,
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                Text(
                                  '${visited[province.id] ?? 0} / ${totals[province.id] ?? 0}',
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }(),
        (AsyncError(), _) ||
        (_, AsyncError()) => const Center(child: Text('지도를 불러오지 못했어요')),
        _ => const Center(child: Text('지도를 불러오는 중이에요')),
      },
    );
  }
}
