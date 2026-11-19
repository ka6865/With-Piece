import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

final originalBytesProvider =
    Provider<Future<Uint8List?> Function(String, PMCancelToken)>(
      (ref) => ref.watch(photoLibraryRepositoryProvider).originalBytes,
    );

final prefetchOriginalProvider =
    Provider<Future<void> Function(String, PMCancelToken)>(
      (ref) => ref.watch(photoLibraryRepositoryProvider).prefetchOriginal,
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

// 동시에 올리는 장수. 원본이 장당 수 MB라 메모리와 맞바꾼다
const uploadWorkers = 5;

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
  static const _originalTimeout = Duration(seconds: 45);
  static const _uploadTimeout = Duration(minutes: 2);
  static const _pendingPrefix = 'pending_photo_upload:';
  // 이 기간 안에 다시 올리면 같은 사진 ID를 써서 중복 행을 막는다
  static const _pendingTtl = Duration(days: 7);
  final _prefetchQueue = <String>{};
  final _prefetched = <String>{};
  final _prefetching = <String, PMCancelToken>{};
  final _reading = <PMCancelToken>{};
  final _cancelOriginal = <PMCancelToken, VoidCallback>{};
  var _stopRequested = false;

  void _cancel(PMCancelToken token) {
    _cancelOriginal[token]?.call();
    unawaited(token.cancelRequest().catchError((Object _) {}));
  }

  Future<T?> _bounded<T>(
    Future<T> Function() operation,
    Duration timeout, {
    PMCancelToken? token,
  }) {
    // 중단하면 원본 읽기가 끝나기를 기다리지 않고 바로 null을 돌려준다
    final stopped = Completer<T?>();
    if (token != null) {
      _cancelOriginal[token] = () {
        if (!stopped.isCompleted) stopped.complete(null);
      };
    }
    return Future.any<T?>([Future.sync(operation), stopped.future])
        .timeout(
          timeout,
          onTimeout: () {
            if (token != null) _cancel(token);
            return null;
          },
        )
        .whenComplete(() => _cancelOriginal.remove(token));
  }

  // 실패한 뒤 다시 올리지 않은 사진의 ID는 남는다. 오래된 것은 지운다
  static void _sweepPendingIds(SharedPreferences prefs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_pendingPrefix)) continue;
      final savedAt = int.tryParse(prefs.getString(key)?.split(' ').last ?? '');
      if (savedAt == null || now - savedAt > _pendingTtl.inMilliseconds) {
        unawaited(prefs.remove(key).catchError((Object _) => false));
      }
    }
  }

  @override
  void dispose() {
    for (final token in [..._prefetching.values, ..._reading]) {
      _cancel(token);
    }
    super.dispose();
  }

  void _drainPrefetch() {
    if (_done != null) return;
    final prefetch = ref.read(prefetchOriginalProvider);
    while (_prefetching.length < 2 && _prefetchQueue.isNotEmpty) {
      final id = _prefetchQueue.first;
      _prefetchQueue.remove(id);
      final token = PMCancelToken();
      _prefetching[id] = token;
      unawaited(
        _bounded(
              () async {
                await prefetch(id, token);
                return true;
              },
              _originalTimeout,
              token: token,
            )
            .then((received) {
              if (received == true && (_selected?.contains(id) ?? false)) {
                _prefetched.add(id);
              }
            })
            .catchError((Object _) {})
            .whenComplete(() {
              _prefetching.remove(id);
              if (mounted) _drainPrefetch();
            }),
      );
    }
  }

  void _setSelected(Set<String> next) {
    final added = next.difference(_selected ?? const {});
    _prefetchQueue.removeWhere((id) => !next.contains(id));
    for (final entry in _prefetching.entries) {
      if (!next.contains(entry.key)) _cancel(entry.value);
    }
    _prefetchQueue.addAll(
      added.where(
        (id) => !_prefetched.contains(id) && !_prefetching.containsKey(id),
      ),
    );
    setState(() => _selected = next);
    _drainPrefetch();
  }

  Future<void> _pickMore() async {
    final picked = await ref.read(libraryPickerProvider)(context);
    if (picked == null || !mounted) return;
    for (final p in picked) {
      if (!_extra.any((e) => e.assetId == p.assetId)) _extra.add(p);
    }
    _setSelected({..._selected!, ...picked.map((p) => p.assetId)});
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
    if (add != true || !mounted) return;
    final repo = ref.read(tripRepositoryProvider);
    final query = widget.query;
    final result = await repo.addRegions(query.tripId, query.coupleId, extra);
    if (!mounted) return;
    final trip = ref
        .read(tripsProvider)
        .value
        ?.where((t) => t.id == query.tripId)
        .firstOrNull;
    final title = trip == null ? null : retitledTrip(trip, extra, names);
    if (result is Ok && title != null) await repo.rename(query.tripId, title);
    if (!mounted) return;
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
    final userId = ref.read(sessionUserIdProvider);
    final prefs = userId == null ? null : ref.read(sharedPreferencesProvider);
    if (prefs != null) _sweepPendingIds(prefs);
    final failed = <LocalPhoto>[];
    final done = <LocalPhoto>[];
    Future<void> uploadOne(LocalPhoto photo) async {
      final token = PMCancelToken();
      _reading.add(token);
      try {
        final original = await _bounded(
          () => readOriginal(photo.assetId, token),
          _originalTimeout,
          token: token,
        );
        _reading.remove(token);
        if (original == null || _stopRequested || !mounted) {
          failed.add(photo);
          return;
        }
        final query = widget.query;
        // 저장 결과를 받기 전에 앱이 종료돼도 다음 시도에서 같은 사진 ID를 쓴다.
        final digest = sha256.convert(
          utf8.encode(
            jsonEncode([userId, query.coupleId, query.tripId, photo.assetId]),
          ),
        );
        final pendingKey = '$_pendingPrefix$digest';
        final previous = prefs?.getString(pendingKey)?.split(' ').first;
        final id = _uploadIds.putIfAbsent(
          pendingKey,
          () => previous ?? uuidV4(),
        );
        if (prefs != null &&
            !await prefs.setString(
              pendingKey,
              '$id ${DateTime.now().millisecondsSinceEpoch}',
            )) {
          failed.add(photo);
          return;
        }
        if (_stopRequested ||
            !mounted ||
            ref.read(sessionUserIdProvider) != userId) {
          failed.add(photo);
          return;
        }
        final result = await _bounded(
          () => repo.upload(
            id: id,
            coupleId: query.coupleId,
            tripId: query.tripId,
            regionId: photo.regionId,
            takenAt: photo.takenAt,
            original: original,
          ),
          _uploadTimeout,
        );
        if (result is! Ok) {
          failed.add(photo);
        } else {
          done.add(photo);
          if (prefs != null) {
            unawaited(prefs.remove(pendingKey).catchError((Object _) => false));
          }
        }
      } catch (_) {
        failed.add(photo);
      } finally {
        _reading.remove(token);
      }
    }

    _stopRequested = false;
    _prefetchQueue.clear();
    for (final token in _prefetching.values) {
      _cancel(token);
    }
    setState(() => _done = 0);
    var next = 0;
    Future<void> worker() async {
      while (!_stopRequested && mounted && next < chosen.length) {
        final photo = chosen[next++];
        await uploadOne(photo);
        if (mounted) setState(() => _done = _done! + 1);
      }
    }

    await Future.wait([for (var i = 0; i < uploadWorkers; i++) worker()]);
    if (!mounted) return;
    if (!_stopRequested && ref.read(sessionUserIdProvider) == userId) {
      await _offerRegions(regionsOutsideTrip(done, widget.query.regionIds));
    }
    if (!mounted) return;
    final stopped = _stopRequested;
    final pending = [...failed, ...chosen.skip(next)];
    setState(() {
      _hasFailures = pending.isNotEmpty;
      _selected = pending.map((photo) => photo.assetId).toSet();
      _done = null;
    });
    if (stopped) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('올리기를 중단했어요. ${done.length}장을 올렸어요')),
      );
      return;
    }
    if (failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${failed.length}장을 올리지 못했어요. 실패한 사진만 선택했어요.')),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${chosen.length}장을 올렸어요')));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
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
              onPressed: !uploading
                  ? () => Navigator.of(context).maybePop()
                  : _stopRequested
                  ? null
                  : () {
                      setState(() => _stopRequested = true);
                      for (final token in _reading) {
                        _cancel(token);
                      }
                    },
              child: Text(uploading ? '중단' : '나중에'),
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
                  onChanged: _setSelected,
                  itemBuilder: (context, id) => _SelectableThumbnail(
                    assetId: id,
                    selected: selected.contains(id),
                    onTap: uploading
                        ? null
                        : () => _setSelected(
                            selected.contains(id)
                                ? selected.difference({id})
                                : {...selected, id},
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

// 사진첩 썸네일. 다시 그릴 때마다 요청하면 끌어 고르는 동안 요청이 쌓여 칸이 비고,
// 결과가 올 때마다 새 이미지로 바뀌어 깜빡인다. 칸마다 한 번만 요청하고, 받은 것은
// 화면 밖으로 나갔다 돌아와도 바로 보이게 기억해 둔다
class LocalThumbnail extends StatefulWidget {
  const LocalThumbnail({super.key, required this.assetId});

  final String assetId;

  // shortcut: 최근 300장(장당 약 10~20KB)만 기억한다. 메모리가 문제되면 줄인다
  static const cacheSize = 300;
  static final _cache = <String, Uint8List>{};

  // 테스트가 사진첩 없이 요청 횟수를 셀 수 있게 바꿔 끼운다
  @visibleForTesting
  static Future<Uint8List?> Function(String id) loader = (id) =>
      AssetEntity.fromId(
        id,
      ).then((a) => a?.thumbnailDataWithSize(const ThumbnailSize.square(200)));

  @visibleForTesting
  static void clearCache() => _cache.clear();

  static void _remember(String id, Uint8List bytes) {
    _cache.remove(id);
    _cache[id] = bytes;
    if (_cache.length > cacheSize) _cache.remove(_cache.keys.first);
  }

  @override
  State<LocalThumbnail> createState() => _LocalThumbnailState();
}

class _LocalThumbnailState extends State<LocalThumbnail> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LocalThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetId != widget.assetId) _load();
  }

  Future<void> _load() async {
    final id = widget.assetId;
    final cached = LocalThumbnail._cache[id];
    if (cached != null) {
      _bytes = cached;
      return;
    }
    _bytes = null;
    final Uint8List? bytes;
    try {
      bytes = await LocalThumbnail.loader(id);
    } catch (_) {
      // 지워졌거나 읽을 수 없는 사진은 빈 칸으로 둔다
      return;
    }
    if (bytes == null) return;
    LocalThumbnail._remember(id, bytes);
    if (mounted && widget.assetId == id) setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    return bytes == null
        ? ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          )
        : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
  }
}
