import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';

import '../../core/result/result.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/repositories/trip_repository.dart';
import '../auth/auth_state.dart';
import '../scan/scan_providers.dart';
import '../trip/photo_upload_page.dart';
import '../trip/region_picker.dart';
import '../trip/trip_candidates_page.dart';
import '../../data/repositories/comment_repository.dart';
import 'album_providers.dart';
import 'comments.dart';
import 'photo_grid.dart';

// 여행 상세. 사진 더하기·지우기(내 사진만), 조각 보정, 제목, 표지(설계 8.4)
class TripDetailPage extends ConsumerWidget {
  const TripDetailPage({
    super.key,
    required this.tripId,
    this.archivedCoupleId,
  });

  final String tripId;
  // 아카이브된 커플의 기록이면 읽기 전용으로 연다(설계 14장)
  final String? archivedCoupleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = archivedCoupleId;
    final readOnly = archived != null;
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
    final trip = trips.value?.where((t) => t.id == tripId).firstOrNull;
    if (trip == null) {
      return Scaffold(
        appBar: AppBar(),
        body: trips.isLoading
            ? const Center(child: CircularProgressIndicator())
            : const Center(child: Text('여행을 찾을 수 없어요')),
      );
    }
    final names = ref.watch(regionNamesProvider).value ?? const {};
    final me = ref.watch(sessionUserIdProvider);
    AsyncValue<List<PhotoRecord>> photosState = const AsyncLoading();
    if (userId != null && archived != null) {
      photosState = ref.watch(
        archivedPhotosProvider((userId: userId, coupleId: archived)),
      );
    } else if (scope != null) {
      photosState = ref.watch(scopedCouplePhotosProvider(scope));
    }
    final photos = [...?photosState.value?.where((p) => p.tripId == tripId)];
    // 화면을 그릴 때가 아니라 누를 때 읽는다. Supabase가 없는 상황에서도 화면은 그린다
    TripRepository repo() => ref.read(tripRepositoryProvider);

    Future<void> run(
      Future<Result<void>> action,
      void Function() refresh,
    ) async {
      final result = await action;
      if (result is Err && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('저장하지 못했어요')));
      }
      refresh();
    }

    return Scaffold(
      key: const Key('trip-detail'),
      appBar: AppBar(
        title: Text(trip.title),
        actions: [
          if (!readOnly)
            IconButton(
              tooltip: '제목 바꾸기',
              icon: const Icon(Icons.edit),
              onPressed: () async {
                final title = await _askTitle(context, trip.title);
                if (title == null) return;
                await run(
                  repo().rename(trip.id, title),
                  () => ref.invalidate(tripsProvider),
                );
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            formatRange(trip.range),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final id in trip.regionIds)
                InputChip(
                  label: Text(names[id] ?? id),
                  // 조각이 하나뿐이면 지울 수 없다. 여행은 조각을 하나 이상 가진다
                  onDeleted: readOnly || trip.regionIds.length < 2
                      ? null
                      : () => run(
                          repo().removeRegion(trip.id, id),
                          () => ref.invalidate(tripsProvider),
                        ),
                ),
              if (!readOnly)
                ActionChip(
                  avatar: const Icon(Icons.add),
                  label: const Text('조각 추가'),
                  onPressed: () async {
                    final coupleState = ref.read(scopedCurrentCoupleProvider);
                    final coupleId =
                        coupleState.isLoading || coupleState.hasError
                        ? null
                        : coupleState.value?.id;
                    final picked = await pickRegions(
                      context,
                      initial: trip.regionIds.toSet(),
                    );
                    if (picked == null || coupleId == null) return;
                    await run(
                      repo().addRegions(
                        trip.id,
                        coupleId,
                        picked.difference(trip.regionIds.toSet()),
                      ),
                      () => ref.invalidate(tripsProvider),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          PhotoGrid(
            photos: photos,
            onLongPress: readOnly
                ? null
                : (photo) => run(
                    repo().setCover(trip.id, photo.id),
                    () => ref.invalidate(tripsProvider),
                  ),
            trailingFor: (photo) => readOnly || photo.uploadedBy != me
                ? null
                : IconButton(
                    tooltip: '사진 지우기',
                    icon: const Icon(Icons.delete, color: Colors.white),
                    onPressed: () => run(
                      ref.read(photoRepositoryProvider).delete(photo),
                      () {
                        if (userId case final id?) {
                          ref.invalidate(couplePhotosProvider(id));
                        }
                      },
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          Text('방명록', style: Theme.of(context).textTheme.titleMedium),
          CommentSection(
            kind: CommentKind.trip,
            targetId: trip.id,
            coupleId: archived ?? scope?.coupleId,
            tripId: trip.id,
          ),
          // 사진 더하기 버튼에 마지막 글이 가리지 않게 한다
          const SizedBox(height: 72),
        ],
      ),
      floatingActionButton: readOnly
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('사진 더하기'),
              onPressed: () async {
                final coupleState = ref.read(scopedCurrentCoupleProvider);
                final coupleId = coupleState.isLoading || coupleState.hasError
                    ? null
                    : coupleState.value?.id;
                if (coupleId == null) return;
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PhotoUploadPage(
                      query: TripPhotoQuery(
                        coupleId: coupleId,
                        tripId: trip.id,
                        range: trip.range,
                        regionIds: trip.regionIds.toSet(),
                      ),
                    ),
                  ),
                );
                if (userId case final id?) {
                  ref.invalidate(couplePhotosProvider(id));
                }
              },
            ),
    );
  }
}

Future<String?> _askTitle(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('제목'),
      content: TextField(controller: controller, autofocus: true),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('저장'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

// 생활권 조각처럼 여행에 묶이지 않은 조각은 그 조각에서 찍은 사진만 모은다(설계 8.4)
class RegionPhotosPage extends ConsumerWidget {
  const RegionPhotosPage({super.key, required this.regionId});

  final String regionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(currentCoupleScopeProvider);
    final names = ref.watch(regionNamesProvider).value ?? const {};
    final photosState = scope == null
        ? const AsyncLoading<List<PhotoRecord>>()
        : ref.watch(scopedCouplePhotosProvider(scope));
    final photos = [
      ...?photosState.value?.where((p) => p.regionId == regionId),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(names[regionId] ?? regionId)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [PhotoGrid(photos: photos)],
      ),
    );
  }
}
