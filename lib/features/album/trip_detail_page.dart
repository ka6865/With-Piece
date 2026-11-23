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
import 'pinch_columns.dart';
import '../../core/ui_confirm.dart';

// 여행 상세. 사진 추가·지우기(내 사진만), 조각 보정, 제목, 표지(설계 8.4)
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
    if (trip == null || trip.status == TripStatus.dismissed) {
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
          if (!readOnly)
            IconButton(
              tooltip: '여행 지우기',
              icon: const Icon(Icons.delete_forever_outlined),
              onPressed:
                  photosState.isLoading ||
                      photosState.hasError ||
                      !photosState.hasValue
                  ? null
                  : () async {
                      // 상대 사진까지 지운다(설계 8.4, 2026-11-23 사용자 결정)
                      final ok = await confirmAction(
                        context,
                        title: '이 여행을 지울까요?',
                        message:
                            '두 사람이 올린 사진 ${photos.length}장과 방명록이 모두 지워져요. '
                            '되돌릴 수 없어요.',
                        action: '지우기',
                      );
                      if (!ok || !context.mounted) return;
                      final result = await repo().deleteTrip(trip.id, [
                        for (final p in photos)
                          if (p.uploadedBy == me) p,
                      ], expectedPhotoCount: photos.length);
                      if (!context.mounted) return;
                      ref.invalidate(tripsProvider);
                      if (userId != null) {
                        ref.invalidate(couplePhotosProvider(userId));
                      }
                      if (result case Err(:final error)) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              error == AppError.validation
                                  ? '여행 기록이 변경됐어요. 사진 수를 다시 확인해 주세요'
                                  : '여행을 지우지 못했어요',
                            ),
                          ),
                        );
                        return;
                      }
                      await Navigator.of(context).maybePop();
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
                      : () async {
                          final ok = await confirmAction(
                            context,
                            title: '${names[id] ?? '이 조각'}을 여행에서 뺄까요?',
                            message: '여행의 사진은 지워지지 않아요.',
                            action: '빼기',
                          );
                          if (!ok) return;
                          await run(
                            repo().removeRegion(trip.id, id),
                            () => ref.invalidate(tripsProvider),
                          );
                        },
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
              if (!readOnly && photos.any((p) => p.uploadedBy == me))
                IconButton(
                  tooltip: '사진 지우기',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final deleted = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => _DeletePhotosPage(
                          photos: [
                            for (final p in photos)
                              if (p.uploadedBy == me) p,
                          ],
                        ),
                      ),
                    );
                    if (deleted == true && userId != null) {
                      ref.invalidate(couplePhotosProvider(userId));
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          PhotoGrid(
            photos: photos,
            allowSave: readOnly,
            onLongPress: readOnly
                ? null
                : (photo) => run(
                    repo().setCover(trip.id, photo.id),
                    () => ref.invalidate(tripsProvider),
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
          // 사진 추가하기 버튼에 마지막 글이 가리지 않게 한다
          const SizedBox(height: 72),
        ],
      ),
      floatingActionButton: readOnly
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('사진 추가하기'),
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

// 내가 올린 사진을 하나 이상 골라 확인을 받고 지운다. 지운 것이 있으면 true로 닫는다
class _DeletePhotosPage extends ConsumerStatefulWidget {
  const _DeletePhotosPage({required this.photos});

  final List<PhotoRecord> photos;

  @override
  ConsumerState<_DeletePhotosPage> createState() => _DeletePhotosPageState();
}

class _DeletePhotosPageState extends ConsumerState<_DeletePhotosPage> {
  final _selected = <String>{};
  bool _deleting = false;
  // 고를 때마다 다시 그리므로 서명 URL은 한 번만 받는다
  late final _urls = ref.read(signedUrlCacheProvider).urls([
    for (final p in widget.photos) p.thumbPath,
  ]);

  Future<void> _delete() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사진 지우기'),
        content: Text('사진 $count장을 정말 지우시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('지우기'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    final repo = ref.read(photoRepositoryProvider);
    var failed = 0;
    for (final photo in widget.photos) {
      if (!_selected.contains(photo.id)) continue;
      if (await repo.delete(photo) is Err) failed++;
    }
    if (!mounted) return;
    if (failed > 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('사진 $failed장을 지우지 못했어요')));
    }
    Navigator.pop(context, failed < count);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selected.isEmpty ? '지울 사진 고르기' : '${_selected.length}장 선택',
        ),
        actions: [
          TextButton(
            onPressed: _deleting || _selected.isEmpty ? null : _delete,
            child: const Text('지우기'),
          ),
        ],
      ),
      body: FutureBuilder<Map<String, String>>(
        future: _urls,
        builder: (context, urls) => PinchColumns(
          kind: 'album',
          defaultColumns: 3,
          builder: (context, columns) => GridView.count(
            padding: const EdgeInsets.all(4),
            crossAxisCount: columns,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            children: [
              for (final photo in widget.photos)
                Semantics(
                  selected: _selected.contains(photo.id),
                  label: '사진 고르기',
                  child: GestureDetector(
                    onTap: _deleting
                        ? null
                        : () => setState(() {
                            if (!_selected.remove(photo.id)) {
                              _selected.add(photo.id);
                            }
                          }),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RemoteImage(url: urls.data?[photo.thumbPath]),
                        if (_selected.contains(photo.id))
                          ColoredBox(
                            color: scheme.primary.withValues(alpha: 0.3),
                          ),
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              _selected.contains(photo.id)
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
