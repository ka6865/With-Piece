import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/media/heic_encoder.dart';
import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/uuid.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/repositories/trip_repository.dart';
import '../scan/scan_providers.dart';
import '../scan/trip_candidates.dart';
import 'drag_select_grid.dart';
import 'photo_selection.dart';

class TripPhotoQuery {
  const TripPhotoQuery({
    required this.coupleId,
    required this.tripId,
    required this.range,
    required this.regionIds,
  });

  final String coupleId;
  final String tripId;
  final DateRange range;
  // 기본 선택 대상인 여행의 조각
  final Set<String> regionIds;

  @override
  bool operator ==(Object other) =>
      other is TripPhotoQuery &&
      other.coupleId == coupleId &&
      other.tripId == tripId &&
      other.range == range &&
      setEquals(other.regionIds, regionIds);

  @override
  int get hashCode =>
      Object.hash(coupleId, tripId, range, Object.hashAllUnordered(regionIds));
}

final photoRepositoryProvider = Provider<PhotoRepository>(
  (ref) =>
      PhotoRepository(ref.watch(supabaseClientProvider), const HeicEncoder()),
);

final originalBytesProvider = Provider<Future<Uint8List?> Function(String)>(
  (ref) => ref.watch(photoLibraryRepositoryProvider).originalBytes,
);

// 기간 안에 찍힌 내 사진. 조각은 기기 안에서 판정하고 서버로 보내지 않는다(설계 5.1).
// 후보 카드 미리보기와 사진 고르기 화면이 같이 쓴다
final localPhotosInRangeProvider =
    FutureProvider.family<List<LocalPhoto>, DateRange>((ref, range) async {
      final locator = await ref.watch(regionLocatorProvider.future);
      final photos =
          (await ref
                  .watch(photoLibraryRepositoryProvider)
                  .photosInRange(range.start, range.end))
              .valueOrThrow;
      return [
        for (final p in photos)
          LocalPhoto(
            assetId: p.id,
            takenAt: p.takenAt,
            regionId: p.location == null ? null : locator.regionAt(p.location!),
          ),
      ];
    });

final tripLocalPhotosProvider =
    FutureProvider.family<List<LocalPhoto>, TripPhotoQuery>(
      (ref, query) => ref.watch(localPhotosInRangeProvider(query.range).future),
    );

// 올린 사진 중 여행에 없는 조각. 속초 여행에 고성에서 찍은 사진을 올렸다면 고성이다
Set<String> regionsOutsideTrip(
  Iterable<LocalPhoto> uploaded,
  Set<String> tripRegions,
) => {
  for (final p in uploaded)
    if (p.regionId case final id? when !tripRegions.contains(id)) id,
};

// 조각을 더한 뒤의 제목. 사용자가 고친 제목이면 건드리지 않는다(null)
String? retitledTrip(
  Trip trip,
  Iterable<String> added,
  Map<String, String> names,
) {
  if (trip.title != candidateTitle(trip.regionIds, trip.range, names)) {
    return null;
  }
  return candidateTitle([...trip.regionIds, ...added], trip.range, names);
}

// 내 사진첩에서 고른 사진만 올린다. 상대 사진은 상대가 올린다(설계 8.0)
class PhotoUploadPage extends ConsumerStatefulWidget {
  const PhotoUploadPage({super.key, required this.query});

  final TripPhotoQuery query;

  @override
  ConsumerState<PhotoUploadPage> createState() => _PhotoUploadPageState();
}

class _PhotoUploadPageState extends ConsumerState<PhotoUploadPage> {
  Set<String>? _selected;
  // 사진첩에서 더 고른 사진. 촬영 날짜가 여행 기간과 달라 기간 목록에 없는 사진이다
  final _extra = <LocalPhoto>[];
  final _uploadIds = <String, String>{};
  int? _done;
  var _hasFailures = false;

  Future<void> _pickMore() async {
    final picked = await ref.read(libraryPickerProvider)(context);
    if (picked == null || !mounted) return;
    setState(() {
      for (final p in picked) {
        if (!_extra.any((e) => e.assetId == p.assetId)) _extra.add(p);
        _selected!.add(p.assetId);
      }
    });
  }

  // 여행에 없는 조각에서 찍은 사진을 올렸으면 그 조각도 여행에 넣을지 묻는다
  // (2026-11-20 사용자 요청: 속초·고성 1박 2일을 함께 묶기)
  Future<void> _offerRegions(Set<String> extra) async {
    if (extra.isEmpty) return;
    Map<String, String> names;
    try {
      names = await ref.read(regionNamesProvider.future);
    } catch (_) {
      names = const {};
    }
    if (!mounted) return;
    final label = extra.map((id) => names[id] ?? id).join(', ');
    final add = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text('$label에서 찍은 사진도 있어요. 이 여행에 $label도 넣을까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('그대로 두기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('넣기'),
          ),
        ],
      ),
    );
    if (add != true) return;
    final repo = ref.read(tripRepositoryProvider);
    final query = widget.query;
    final result = await repo.addRegions(query.tripId, query.coupleId, extra);
    final trip = ref
        .read(tripsProvider)
        .value
        ?.where((t) => t.id == query.tripId)
        .firstOrNull;
    final title = trip == null ? null : retitledTrip(trip, extra, names);
    if (result is Ok && title != null) await repo.rename(query.tripId, title);
    ref.invalidate(tripsProvider);
    if (result is Err && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('조각을 넣지 못했어요')));
    }
  }

  Future<void> _upload(List<LocalPhoto> photos) async {
    final chosen = [
      for (final p in photos)
        if (_selected!.contains(p.assetId)) p,
    ];
    final repo = ref.read(photoRepositoryProvider);
    final readOriginal = ref.read(originalBytesProvider);
    final failed = <LocalPhoto>[];
    final done = <LocalPhoto>[];
    Future<void> uploadOne(LocalPhoto photo) async {
      try {
        final original = await readOriginal(photo.assetId);
        final result = original == null
            ? const Err<String>(AppError.unknown)
            : await repo.upload(
                id: _uploadIds.putIfAbsent(photo.assetId, uuidV4),
                coupleId: widget.query.coupleId,
                tripId: widget.query.tripId,
                regionId: photo.regionId,
                takenAt: photo.takenAt,
                original: original,
              );
        (result is Err ? failed : done).add(photo);
      } catch (_) {
        failed.add(photo);
      }
    }

    setState(() => _done = 0);
    // 원본 읽기(iCloud 다운로드 포함)·변환·업로드를 사진마다 기다리지 않도록 몇 장씩
    // 동시에 처리한다. 원본이 장당 수 MB라 메모리를 생각해 3장으로 둔다
    var next = 0;
    Future<void> worker() async {
      while (next < chosen.length) {
        final photo = chosen[next++];
        await uploadOne(photo);
        if (!mounted) return;
        setState(() => _done = _done! + 1);
      }
    }

    await Future.wait([for (var i = 0; i < 3; i++) worker()]);
    if (!mounted) return;
    await _offerRegions(regionsOutsideTrip(done, widget.query.regionIds));
    if (!mounted) return;
    setState(() {
      _hasFailures = failed.isNotEmpty;
      _selected = failed.map((photo) => photo.assetId).toSet();
      _done = null;
    });
    if (failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${failed.length}장을 올리지 못했어요. 실패한 사진만 선택했어요.')),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${chosen.length}장을 올렸어요')));
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(tripLocalPhotosProvider(widget.query));
    final inRange = photos.value;
    // 미리 골라 두지 않는다. 사용자가 직접 고른다(2026-11-20 사용자 결정, 설계 8.0)
    if (inRange != null) _selected ??= {};
    final list = inRange == null
        ? null
        : [
            ...inRange,
            ..._extra.where((e) => !inRange.any((p) => p.assetId == e.assetId)),
          ];
    final selected = _selected ?? const <String>{};
    final uploading = _done != null;
    return PopScope(
      canPop: !uploading,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('사진 고르기'),
          actions: [
            TextButton(
              onPressed: uploading
                  ? null
                  : () => Navigator.of(context).maybePop(),
              child: const Text('나중에'),
            ),
          ],
        ),
        body: switch (photos) {
          AsyncValue(hasValue: true) => Column(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.photo_library),
                label: const Text('사진첩에서 더 고르기'),
                onPressed: uploading ? null : _pickMore,
              ),
              Expanded(
                child: DragSelectGrid(
                  ids: [for (final p in list!) p.assetId],
                  selected: selected,
                  enabled: !uploading,
                  onChanged: (next) => setState(() => _selected = next),
                  itemBuilder: (context, id) => _SelectableThumbnail(
                    assetId: id,
                    selected: selected.contains(id),
                    onTap: uploading
                        ? null
                        : () => setState(
                            () => selected.contains(id)
                                ? _selected!.remove(id)
                                : _selected!.add(id),
                          ),
                  ),
                ),
              ),
            ],
          ),
          AsyncValue(error: AppError.photoPermission) => const Center(
            child: Text('사진 전체 접근을 허용해야 고를 수 있어요'),
          ),
          AsyncValue(hasError: true) => const Center(
            child: Text('사진을 불러오지 못했어요'),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: list == null || selected.isEmpty || uploading
                  ? null
                  : () => _upload(list),
              child: Text(
                uploading
                    ? '$_done / ${selected.length} 올리는 중'
                    : _hasFailures
                    ? '${selected.length}장 다시 올리기'
                    : '${selected.length}장 올리기',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectableThumbnail extends StatelessWidget {
  const _SelectableThumbnail({
    required this.assetId,
    required this.selected,
    required this.onTap,
  });

  final String assetId;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Stack(
      fit: StackFit.expand,
      children: [
        LocalThumbnail(assetId: assetId),
        if (selected)
          const Align(
            alignment: Alignment.topRight,
            child: Icon(Icons.check_circle, color: Colors.white),
          ),
      ],
    ),
  );
}

// 사진첩 전체를 최신순으로 보며 여러 장을 고른다. 날짜·위치와 무관하게 고를 수 있다
class LibraryPickerPage extends ConsumerStatefulWidget {
  const LibraryPickerPage({super.key});

  static const pageSize = 120;

  @override
  ConsumerState<LibraryPickerPage> createState() => _LibraryPickerPageState();
}

class _LibraryPickerPageState extends ConsumerState<LibraryPickerPage> {
  final _photos = <LocalPhoto>[];
  final _selected = <String>{};
  var _page = 0;
  var _loading = false;
  var _exhausted = false;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _exhausted) return;
    setState(() => _loading = true);
    final locator = await ref.read(regionLocatorProvider.future);
    final result = await ref
        .read(photoLibraryRepositoryProvider)
        .recentPhotos(page: _page, size: LibraryPickerPage.pageSize);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result case Ok(:final value)) {
        _page++;
        _exhausted = value.length < LibraryPickerPage.pageSize;
        _photos.addAll([
          for (final p in value)
            LocalPhoto(
              assetId: p.id,
              takenAt: p.takenAt,
              regionId: p.location == null
                  ? null
                  : locator.regionAt(p.location!),
            ),
        ]);
      } else {
        _exhausted = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('사진첩')),
    body: NotificationListener<ScrollEndNotification>(
      onNotification: (n) {
        if (n.metrics.extentAfter < 400) _loadMore();
        return false;
      },
      child: DragSelectGrid(
        ids: [for (final p in _photos) p.assetId],
        selected: _selected,
        onChanged: (next) => setState(
          () => _selected
            ..clear()
            ..addAll(next),
        ),
        itemBuilder: (context, id) => _SelectableThumbnail(
          assetId: id,
          selected: _selected.contains(id),
          onTap: () => setState(
            () => _selected.contains(id)
                ? _selected.remove(id)
                : _selected.add(id),
          ),
        ),
      ),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, [
                  for (final p in _photos)
                    if (_selected.contains(p.assetId)) p,
                ]),
          child: Text('${_selected.length}장 추가'),
        ),
      ),
    ),
  );
}

// 테스트가 사진첩 화면 없이 고른 결과를 넣을 수 있게 provider로 둔다
final libraryPickerProvider =
    Provider<Future<List<LocalPhoto>?> Function(BuildContext)>(
      (ref) =>
          (context) => Navigator.of(context).push<List<LocalPhoto>>(
            MaterialPageRoute(builder: (_) => const LibraryPickerPage()),
          ),
    );

class LocalThumbnail extends StatelessWidget {
  const LocalThumbnail({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: AssetEntity.fromId(
      assetId,
    ).then((a) => a?.thumbnailDataWithSize(const ThumbnailSize.square(200))),
    builder: (context, snapshot) => snapshot.data == null
        ? ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          )
        : Image.memory(snapshot.data!, fit: BoxFit.cover),
  );
}
