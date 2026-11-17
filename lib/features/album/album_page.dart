import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../scan/scan_providers.dart';
import '../auth/auth_state.dart';
import '../trip/trip_candidates_page.dart';
import 'album_providers.dart';
import 'photo_grid.dart';

// 확인된 여행을 최신순으로 본다. 지도가 "어디"라면 앨범은 "언제"다(설계 8.4)
class AlbumPage extends ConsumerWidget {
  const AlbumPage({super.key, this.archivedCoupleId});

  // 아카이브된 커플의 기록이면 그 커플의 여행을 읽기 전용으로 본다(설계 14장)
  final String? archivedCoupleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = archivedCoupleId;
    final userId = ref.watch(sessionUserIdProvider);
    final scope = ref.watch(currentCoupleScopeProvider);
    AsyncValue<List<Trip>> trips = const AsyncLoading();
    if (userId != null && archived != null) {
      trips = ref.watch(
        archivedTripsProvider((userId: userId, coupleId: archived)),
      );
    } else if (scope != null) {
      trips = ref.watch(scopedTripsProvider(scope));
    }
    AsyncValue<List<PhotoRecord>> photosState = const AsyncLoading();
    if (userId != null && archived != null) {
      photosState = ref.watch(
        archivedPhotosProvider((userId: userId, coupleId: archived)),
      );
    } else if (scope != null) {
      photosState = ref.watch(scopedCouplePhotosProvider(scope));
    }
    final photos = photosState.value ?? const <PhotoRecord>[];
    final names = ref.watch(regionNamesProvider).value ?? const {};
    final tripRows = trips.value;
    final confirmed = [
      ...?tripRows?.where((t) => t.status == TripStatus.confirmed),
    ]..sort((a, b) => b.range.start.compareTo(a.range.start));
    final covers = {
      for (final trip in confirmed) trip.id: ?_coverOf(trip, photos),
    };
    return Scaffold(
      appBar: AppBar(title: Text(archived == null ? '퍼즐 앨범' : '지난 기록')),
      body: trips.hasValue
          ? confirmed.isEmpty
                ? const Center(child: Text('아직 확인한 여행이 없어요'))
                : FutureBuilder<Map<String, String>>(
                    key: ValueKey((
                      userId: userId,
                      coupleId: archived ?? scope?.coupleId,
                    )),
                    future: ref.watch(signedUrlCacheProvider).urls([
                      for (final c in covers.values) c.thumbPath,
                    ]),
                    builder: (context, urls) => ListView(
                      children: [
                        for (final trip in confirmed)
                          ListTile(
                            leading: SizedBox.square(
                              dimension: 56,
                              child: RemoteImage(
                                url: urls.data?[covers[trip.id]?.thumbPath],
                              ),
                            ),
                            title: Text(
                              trip.title,
                              key: const Key('album-title'),
                            ),
                            subtitle: Text(
                              '${formatRange(trip.range)} · '
                              '${trip.regionIds.map((id) => names[id] ?? id).join(' · ')}\n'
                              '사진 ${photos.where((p) => p.tripId == trip.id).length}장',
                            ),
                            isThreeLine: true,
                            onTap: () => context.push(
                              archived == null
                                  ? '/trips/${trip.id}'
                                  : '/archive/$archived/trips/${trip.id}',
                            ),
                          ),
                      ],
                    ),
                  )
          : trips.hasError
          ? const Center(child: Text('앨범을 불러오지 못했어요'))
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

PhotoRecord? _coverOf(Trip trip, List<PhotoRecord> photos) {
  final mine = photos.where((p) => p.tripId == trip.id);
  return mine.where((p) => p.id == trip.coverPhotoId).firstOrNull ??
      mine.firstOrNull;
}
