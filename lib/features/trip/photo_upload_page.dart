import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/media/heic_encoder.dart';
import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../scan/scan_providers.dart';
import '../scan/trip_candidates.dart';
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
  int? _done;

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

  Future<void> _upload(List<LocalPhoto> photos) async {
    final chosen = [
      for (final p in photos)
        if (_selected!.contains(p.assetId)) p,
    ];
    final repo = ref.read(photoRepositoryProvider);
    final readOriginal = ref.read(originalBytesProvider);
    var failed = 0;
    setState(() => _done = 0);
    for (final photo in chosen) {
      final original = await readOriginal(photo.assetId);
      final result = original == null
          ? const Err<String>(AppError.unknown)
          : await repo.upload(
              coupleId: widget.query.coupleId,
              tripId: widget.query.tripId,
              regionId: photo.regionId,
              takenAt: photo.takenAt,
              original: original,
            );
      if (result is Err) failed++;
      if (!mounted) return;
      setState(() => _done = _done! + 1);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0 ? '${chosen.length}장을 올렸어요' : '$failed장을 올리지 못했어요',
        ),
      ),
    );
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final photos = ref.watch(tripLocalPhotosProvider(widget.query));
    final inRange = photos.value;
    if (inRange != null) {
      // 여행에 포함된 조각의 사진만 기본 선택한다(설계 8.0)
      _selected ??= defaultSelection(inRange, regions: widget.query.regionIds);
    }
    final list = inRange == null
        ? null
        : [
            ...inRange,
            ..._extra.where((e) => !inRange.any((p) => p.assetId == e.assetId)),
          ];
    final selected = _selected ?? const <String>{};
    final uploading = _done != null;
    return Scaffold(
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
              child: GridView.count(
                crossAxisCount: 4,
                padding: const EdgeInsets.all(2),
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
                children: [
                  for (final p in list!)
                    _SelectableThumbnail(
                      assetId: p.assetId,
                      selected: selected.contains(p.assetId),
                      onTap: uploading
                          ? null
                          : () => setState(
                              () => selected.contains(p.assetId)
                                  ? _selected!.remove(p.assetId)
                                  : _selected!.add(p.assetId),
                            ),
                    ),
                ],
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
                  : '${selected.length}장 올리기',
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
      child: GridView.count(
        crossAxisCount: 4,
        padding: const EdgeInsets.all(2),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        children: [
          for (final p in _photos)
            _SelectableThumbnail(
              assetId: p.assetId,
              selected: _selected.contains(p.assetId),
              onTap: () => setState(
                () => _selected.contains(p.assetId)
                    ? _selected.remove(p.assetId)
                    : _selected.add(p.assetId),
              ),
            ),
        ],
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
