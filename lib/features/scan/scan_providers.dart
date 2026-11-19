import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/result/result.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/repositories/trip_repository.dart';
import '../../map_data/geo_region_locator.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../map_data/map_asset_loader.dart';
import '../auth/auth_state.dart';
import 'home_regions.dart';
import 'progress.dart';
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
  final userId = ref.watch(sessionUserIdProvider);
  final coupleFuture = ref.watch(currentCoupleProvider.future);
  if (userId == null) return;
  var cancelled = false;
  ref.onDispose(() => cancelled = true);
  final couple = await coupleFuture;
  final startedOn = couple?.startedOn;
  if (couple == null || startedOn == null || cancelled) return;
  final sync = ref.watch(scanSyncProvider);
  final snapshotFuture = ref.watch(scanSnapshotProvider.future);
  final snapshot = await snapshotFuture;
  if (cancelled || !ref.mounted || ref.read(sessionUserIdProvider) != userId) {
    return;
  }
  final latest = ref.read(currentCoupleProvider).unwrapPrevious().value;
  if (latest?.id != couple.id || latest?.startedOn != startedOn) return;
  (await sync.sync(
    snapshot,
    startedOn,
    userId: userId,
    coupleId: couple.id,
  )).valueOrThrow;
});

final matchedDaysProvider = FutureProvider<List<PhotoDay>>((ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  final synced = ref.watch(photoDaysSyncedProvider.future);
  if (userId == null) return const [];
  final repository = ref.watch(tripRepositoryProvider);
  await synced;
  if (!ref.mounted) return const [];
  return (await repository.matchedDays()).valueOrThrow;
});

Future<String?> _coupleId(Ref ref) async {
  final userId = ref.watch(sessionUserIdProvider);
  final coupleFuture = ref.watch(currentCoupleProvider.future);
  if (userId == null) return null;
  return (await coupleFuture)?.id;
}

final tripsProvider = FutureProvider<List<Trip>>((ref) async {
  final coupleFuture = _coupleId(ref);
  final repository = ref.watch(tripRepositoryProvider);
  final coupleId = await coupleFuture;
  if (coupleId == null || !ref.mounted) return const [];
  return (await repository.trips(coupleId)).valueOrThrow;
});

final overridesProvider = FutureProvider<Map<String, OverrideKind>>((
  ref,
) async {
  final coupleFuture = _coupleId(ref);
  final repository = ref.watch(tripRepositoryProvider);
  final coupleId = await coupleFuture;
  if (coupleId == null || !ref.mounted) return const {};
  return (await repository.overrides(coupleId)).valueOrThrow;
});

final homeRegionIdsProvider = FutureProvider<Set<String>>((ref) async {
  ref.watch(sessionUserIdProvider);
  final days = ref.watch(matchedDaysProvider.future);
  final overrides = ref.watch(overridesProvider.future);
  return homeRegions(await days, await overrides);
});

// 여행 확인 직전 채운 조각. 아직 읽지 못했으면 null이고 확인 문구가 조각 수를
// 말하지 않는다(커플 디자인 4.7)
Set<String>? filledRegionIdsNow(WidgetRef ref) {
  final trips = ref.read(tripsProvider).value;
  final home = ref.read(homeRegionIdsProvider).value;
  return trips == null || home == null ? null : filledRegionIds(trips, home);
}

// family가 바뀌면 이전 계정·커플의 AsyncValue를 이어받지 않는다.
final scopedTripsProvider = FutureProvider.autoDispose
    .family<List<Trip>, CoupleScope>((ref, scope) {
      if (ref.watch(currentCoupleScopeProvider) != scope) return const [];
      return ref.watch(tripsProvider.future);
    });

final scopedHomeRegionIdsProvider = FutureProvider.autoDispose
    .family<Set<String>, CoupleScope>((ref, scope) {
      if (ref.watch(currentCoupleScopeProvider) != scope) return const {};
      return ref.watch(homeRegionIdsProvider.future);
    });

final regionNamesProvider = FutureProvider<Map<String, String>>((ref) async {
  final asset = await ref.watch(regionMapAssetProvider.future);
  return {for (final f in asset.features) f.id: f.name};
});

final tripCandidatesProvider = FutureProvider<List<TripCandidate>>((ref) async {
  final scope = ref.watch(currentCoupleScopeProvider);
  if (scope == null) return const [];
  final days = ref.watch(matchedDaysProvider.future);
  final home = ref.watch(scopedHomeRegionIdsProvider(scope).future);
  final trips = ref.watch(scopedTripsProvider(scope).future);
  final names = ref.watch(regionNamesProvider.future);
  return tripCandidates(
    await days,
    home: await home,
    existing: [for (final t in await trips) t.range],
    regionNames: await names,
  );
});

// 로딩 중인 커플도 계정 키를 가지므로 이전 사용자의 후보를 이어받지 않는다.
typedef CandidateScope = ({String? userId, String? coupleId});
final candidateScopeProvider = Provider<CandidateScope>(
  (ref) => (
    userId: ref.watch(sessionUserIdProvider),
    coupleId: ref.watch(currentCoupleScopeProvider)?.coupleId,
  ),
);
final _candidatesForScopeProvider = FutureProvider.autoDispose
    .family<List<TripCandidate>, CandidateScope>((ref, scope) {
      if (ref.watch(candidateScopeProvider) != scope) return const [];
      return ref.watch(tripCandidatesProvider.future);
    });
final scopedTripCandidatesProvider = Provider<AsyncValue<List<TripCandidate>>>(
  (ref) =>
      ref.watch(_candidatesForScopeProvider(ref.watch(candidateScopeProvider))),
);
