import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../map_data/map_asset.dart';
import '../../../map_data/map_asset_loader.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../data/repositories/trip_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../auth/auth_state.dart';
import '../../scan/home_regions.dart';
import '../../scan/progress.dart';
import '../../scan/scan_providers.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../album/album_providers.dart';
import '../painter/puzzle_painter.dart';
import '../region_covers.dart';
import 'puzzle_map.dart';

class ProvinceMapPage extends ConsumerWidget {
  const ProvinceMapPage({super.key, required this.provinceId});

  final String provinceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provinces = ref.watch(provinceMapAssetProvider);
    final regions = ref.watch(regionMapAssetProvider);
    // 진행 데이터가 없거나 오류여도 지도는 그린다(설계 12장)
    final scope = ref.watch(currentCoupleScopeProvider);
    final trips =
        (scope == null ? null : ref.watch(scopedTripsProvider(scope)).value) ??
        const <Trip>[];
    final home =
        (scope == null
            ? null
            : ref.watch(scopedHomeRegionIdsProvider(scope)).value) ??
        const <String>{};
    final travel = filledRegionIds(trips, const {});
    final photos =
        (scope == null
            ? null
            : ref.watch(scopedCouplePhotosProvider(scope)).value) ??
        const <PhotoRecord>[];
    final effective = effectiveCovers(
      ref.watch(regionCoversProvider).value ?? const {},
      photos,
    );
    return switch ((provinces, regions)) {
      (
        AsyncData(value: final provinceAsset),
        AsyncData(value: final regionAsset),
      ) =>
        () {
          final province = provinceAsset.byId(provinceId);
          final asset = province == null
              ? null
              : provinceAssetOf(regionAsset, provinceId);
          if (province == null || asset == null) {
            return Scaffold(
              appBar: AppBar(),
              body: const Center(child: Text('지역을 찾을 수 없어요')),
            );
          }
          // 채운 조각만 사진으로 채운다. 사진을 받는 동안은 면 색이다
          final covers = <String, CoverImage>{
            for (final MapEntry(key: id, value: (photo, cover))
                in effective.entries)
              if (asset.byId(id) != null &&
                  (travel.contains(id) || home.contains(id)))
                if (ref.watch(coverImageProvider(photo.fullPath)).value
                    case final image?)
                  id: (image: image, cover: cover),
          };
          return Scaffold(
            appBar: AppBar(title: Text(province.name)),
            body: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: PuzzleMap(
                      asset: asset,
                      visitedRegionIds: travel,
                      homeRegionIds: home,
                      covers: covers,
                      // 채운 조각은 조각 화면, 빈 조각은 수동 여행 만들기(설계 5.5, 4.3)
                      onRegionTap: (id) => context.push(
                        travel.contains(id) || home.contains(id)
                            ? '/regions/$id'
                            : '/trips/new?region=$id',
                      ),
                      onRegionLongPress: (id) => _changeKind(
                        context,
                        ref,
                        id,
                        home: home.contains(id),
                        travel: travel.contains(id),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '${asset.features.where((f) => travel.contains(f.id) || home.contains(f.id)).length}'
                    ' / ${asset.features.length} 조각',
                  ),
                ),
              ],
            ),
          );
        }(),
      (AsyncError(), _) || (_, AsyncError()) => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('지도를 불러오지 못했어요')),
      ),
      _ => Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('지도를 불러오는 중이에요')),
      ),
    };
  }
}

// 생활권 자동 분류를 두 사람 누구든 조각별로 고친다(설계 5.3)
Future<void> _changeKind(
  BuildContext context,
  WidgetRef ref,
  String regionId, {
  required bool home,
  required bool travel,
}) async {
  if (!home && !travel) return;
  // 이 화면은 커플 provider를 구독하지 않으므로 값을 기다려 읽는다
  final coupleId = (await ref.read(currentCoupleProvider.future))?.id;
  if (coupleId == null || !context.mounted) return;
  final kind = await showModalBottomSheet<OverrideKind>(
    context: context,
    builder: (context) => SafeArea(
      child: ListTile(
        title: Text(home ? '여행지로 바꾸기' : '생활권으로 바꾸기'),
        onTap: () => Navigator.pop(
          context,
          home ? OverrideKind.travel : OverrideKind.home,
        ),
      ),
    ),
  );
  if (kind == null) return;
  final result = await ref
      .read(tripRepositoryProvider)
      .setOverride(coupleId, regionId, kind);
  if (result is Err && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('바꾸지 못했어요')));
  }
  ref.invalidate(overridesProvider);
}

// 시도 하나의 조각만 담은 애셋. 뷰포트는 그 조각들의 경위도에서 계산하고,
// 인셋은 원본 인셋이 속한 시도(경북)일 때만 유지한다
MapAsset? provinceAssetOf(MapAsset regionAsset, String provinceId) =>
    _cachedDerivedAsset((regionAsset, provinceId, true), () {
      final features = regionAsset.features
          .where((f) => f.parentId == provinceId)
          .toList();
      if (features.isEmpty) return null;
      final featureIds = {for (final f in features) f.id};
      final insets = regionAsset.insets
          .where((i) => featureIds.contains(i.regionId))
          .toList();
      return _assetOf(regionAsset, features, insets);
    });

// 조각 하나의 모양만 담은 애셋. 구도 맞춤 화면의 틀로 쓴다. 인셋 없이 모든 폴리곤을
// 한 뷰포트에 넣는다(울릉군처럼 인셋에만 있는 조각도 그려지게)
MapAsset? regionShapeAssetOf(MapAsset regionAsset, String regionId) =>
    _cachedDerivedAsset((regionAsset, regionId, false), () {
      final feature = regionAsset.byId(regionId);
      if (feature == null) return null;
      return _assetOf(regionAsset, [feature], const []);
    });

// shortcut: 최근 32개 파생 애셋만 유지, 시도 전환으로 자주 재생성되면 상향한다
final _derivedAssets = <(MapAsset, String, bool), MapAsset>{};
MapAsset? _cachedDerivedAsset(
  (MapAsset, String, bool) key,
  MapAsset? Function() build,
) {
  final cached = _derivedAssets.remove(key);
  if (cached != null) {
    _derivedAssets[key] = cached;
    return cached;
  }
  final asset = build();
  if (asset == null) return null;
  _derivedAssets[key] = asset;
  if (_derivedAssets.length > 32) {
    _derivedAssets.remove(_derivedAssets.keys.first);
  }
  return asset;
}

MapAsset _assetOf(
  MapAsset regionAsset,
  List<MapFeature> features,
  List<MapInset> insets,
) {
  final insetRegionIds = {for (final i in insets) i.regionId};
  final points = [
    for (final f in features)
      if (!insetRegionIds.contains(f.id))
        for (final polygon in f.polygons)
          for (final ring in polygon) ...ring,
  ];
  double pick(
    double Function(GeoPoint) of,
    bool Function(double, double) better,
  ) => points.map(of).reduce((a, b) => better(a, b) ? a : b);
  return MapAsset(
    version: regionAsset.version,
    mainlandBbox: GeoBbox(
      pick((p) => p.lon, (a, b) => a < b),
      pick((p) => p.lat, (a, b) => a < b),
      pick((p) => p.lon, (a, b) => a > b),
      pick((p) => p.lat, (a, b) => a > b),
    ),
    insets: insets,
    features: features,
  );
}
