import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../map_data/map_asset_loader.dart';
import '../../scan/progress.dart';
import '../../auth/auth_state.dart';
import '../../scan/realtime_sync.dart';
import '../../scan/scan_providers.dart';
import '../../trip/trip_discovery_banner.dart';
import 'puzzle_map.dart';

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
        actions: [
          IconButton(
            tooltip: '퍼즐 앨범',
            icon: const Icon(Icons.photo_album),
            onPressed: () => context.push('/album'),
          ),
          IconButton(
            tooltip: '계정 연결',
            icon: const Icon(Icons.manage_accounts),
            onPressed: () => context.push('/settings/accounts'),
          ),
        ],
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
                if (scope != null) const TripDiscoveryBanner(),
                // 바다가 화면 가장자리까지 이어지도록 여백 없이 둔다
                Expanded(
                  child: PuzzleMap(
                    asset: provinceAsset,
                    // 한 조각이라도 칠해진 시도를 채운다
                    visitedRegionIds: visited.keys.toSet(),
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
                      spacing: 16,
                      children: [
                        for (final province in provinceAsset.features)
                          Column(
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
