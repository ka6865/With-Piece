import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/couple_repository.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/repositories/trip_repository.dart';
import '../../data/repositories/signed_url_cache.dart';
import '../auth/auth_state.dart';
import '../trip/photo_upload_page.dart';

final couplePhotosProvider = FutureProvider.family<List<PhotoRecord>, String>((
  ref,
  userId,
) async {
  if (ref.watch(sessionUserIdProvider) != userId) return const [];
  final coupleFuture = ref.watch(currentCoupleProvider.future);
  final repository = ref.watch(photoRepositoryProvider);
  final coupleId = (await coupleFuture)?.id;
  if (coupleId == null || !ref.mounted) return const [];
  return (await repository.forCouple(coupleId)).valueOrThrow;
});

final scopedCouplePhotosProvider = FutureProvider.autoDispose
    .family<List<PhotoRecord>, CoupleScope>((ref, scope) {
      if (ref.watch(currentCoupleScopeProvider) != scope) return const [];
      return ref.watch(couplePhotosProvider(scope.userId).future);
    });

// 앱 전체에서 하나를 쓴다. 화면을 오가도 유효한 URL을 다시 받지 않는다
final signedUrlCacheProvider = Provider<SignedUrlCache>((ref) {
  ref.watch(sessionUserIdProvider);
  final storage = ref
      .watch(supabaseClientProvider)
      .storage
      .from(PhotoRepository.bucket);
  return SignedUrlCache((paths) async {
    final signed = await storage.createSignedUrlsResult(
      paths,
      SignedUrlCache.ttl.inSeconds,
    );
    // 지워진 사진처럼 서명하지 못한 경로는 빼고, 화면은 자리 표시로 그린다
    return {
      for (final s in signed)
        if (s case SignedUrlSuccess(:final path, :final signedUrl))
          path: signedUrl,
    };
  });
});

// 아카이브된 커플의 기록. RLS가 읽기만 허용한다(설계 9장, 14장)
final archivedCouplesProvider =
    FutureProvider.family<List<ArchivedCouple>, String>((ref, userId) async {
      if (ref.watch(sessionUserIdProvider) != userId) return const [];
      return (await ref.watch(coupleRepositoryProvider).archived())
          .valueOrThrow;
    });

typedef ArchivedCoupleScope = ({String userId, String coupleId});

final archivedTripsProvider =
    FutureProvider.family<List<Trip>, ArchivedCoupleScope>((ref, scope) async {
      if (ref.watch(sessionUserIdProvider) != scope.userId) return const [];
      return (await ref.watch(tripRepositoryProvider).trips(scope.coupleId))
          .valueOrThrow;
    });

final archivedPhotosProvider =
    FutureProvider.family<List<PhotoRecord>, ArchivedCoupleScope>((
      ref,
      scope,
    ) async {
      if (ref.watch(sessionUserIdProvider) != scope.userId) return const [];
      return (await ref
              .watch(photoRepositoryProvider)
              .forCouple(scope.coupleId))
          .valueOrThrow;
    });
