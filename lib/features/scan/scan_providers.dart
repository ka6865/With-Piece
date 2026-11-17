import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/result/result.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/repositories/trip_repository.dart';
import '../../map_data/geo_region_locator.dart';
import '../../map_data/map_asset_loader.dart';
import '../auth/auth_state.dart';
import 'home_regions.dart';
import 'photo_days.dart';
import 'scan_store.dart';
import 'scan_sync.dart';
import 'scanner.dart';
import 'trip_candidates.dart';

// 스캔 → 사귄 날 기준 업로드 → 교집합 → 생활권·후보 계산(설계 5장)

final regionLocatorProvider = FutureProvider<GeoRegionLocator>(
  (ref) async =>
      GeoRegionLocator(await ref.watch(regionMapAssetProvider.future)),
);

final scanStoreProvider = FutureProvider<ScanStore>(
  (ref) async => ScanStore(await getApplicationDocumentsDirectory()),
);

// 처음 읽을 때 사진 권한을 묻는다. 권한이 없으면 AppError.photoPermission
final scanSnapshotProvider = FutureProvider<ScanSnapshot>((ref) async {
  final scanner = Scanner(
    ref.watch(photoLibraryRepositoryProvider),
    await ref.watch(regionLocatorProvider.future),
    await ref.watch(scanStoreProvider.future),
  );
  return (await scanner.scan()).valueOrThrow;
});

final scanSyncProvider = Provider<ScanSync>(
  (ref) => ScanSync(
    ref.watch(photoDayRepositoryProvider),
    ref.watch(sharedPreferencesProvider),
  ),
);

// 사귄 날이 바뀌면(상대가 바꿔도) currentCoupleProvider가 다시 읽혀 다시 맞춘다
final photoDaysSyncedProvider = FutureProvider<void>((ref) async {
  final snapshot = await ref.watch(scanSnapshotProvider.future);
  final startedOn = (await ref.watch(currentCoupleProvider.future))?.startedOn;
  if (startedOn == null) return;
  (await ref.watch(scanSyncProvider).sync(snapshot, startedOn)).valueOrThrow;
});

final matchedDaysProvider = FutureProvider<List<PhotoDay>>((ref) async {
  await ref.watch(photoDaysSyncedProvider.future);
  return (await ref.watch(tripRepositoryProvider).matchedDays()).valueOrThrow;
});

Future<String?> _coupleId(Ref ref) async =>
    (await ref.watch(currentCoupleProvider.future))?.id;

final tripsProvider = FutureProvider<List<Trip>>((ref) async {
  final coupleId = await _coupleId(ref);
  if (coupleId == null) return const [];
  return (await ref.watch(tripRepositoryProvider).trips(coupleId)).valueOrThrow;
});

final overridesProvider = FutureProvider<Map<String, OverrideKind>>((
  ref,
) async {
  final coupleId = await _coupleId(ref);
  if (coupleId == null) return const {};
  return (await ref.watch(tripRepositoryProvider).overrides(coupleId))
      .valueOrThrow;
});

final homeRegionIdsProvider = FutureProvider<Set<String>>(
  (ref) async => homeRegions(
    await ref.watch(matchedDaysProvider.future),
    await ref.watch(overridesProvider.future),
  ),
);

final regionNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final asset = await ref.watch(regionMapAssetProvider.future);
  return {for (final f in asset.features) f.id: f.name};
});

final tripCandidatesProvider = FutureProvider<List<TripCandidate>>(
  (ref) async => tripCandidates(
    await ref.watch(matchedDaysProvider.future),
    home: await ref.watch(homeRegionIdsProvider.future),
    existing: [for (final t in await ref.watch(tripsProvider.future)) t.range],
    regionNames: await ref.watch(regionNamesProvider.future),
  ),
);
