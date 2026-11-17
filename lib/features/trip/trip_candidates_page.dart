import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/repositories/trip_repository.dart';
import '../scan/scan_providers.dart';
import '../scan/trip_candidates.dart';
import '../auth/auth_state.dart';
import 'photo_upload_page.dart';
import 'trip_confirm_sheet.dart';

String formatRange(DateRange range) {
  final s = range.start;
  final e = range.end;
  final start = '${s.year}.${s.month}.${s.day}';
  if (range.nights == 0) return start;
  final end = e.year == s.year
      ? '${e.month}.${e.day}'
      : '${e.year}.${e.month}.${e.day}';
  return '$start ~ $end';
}

// 함께 간 날을 묶은 후보를 확인하거나 버린다. 한 사람만 확인해도 칠해진다(설계 5.4)
class TripCandidatesPage extends ConsumerStatefulWidget {
  const TripCandidatesPage({super.key});

  @override
  ConsumerState<TripCandidatesPage> createState() => _TripCandidatesPageState();
}

class _TripCandidatesPageState extends ConsumerState<TripCandidatesPage> {
  List<_CandidateEntry>? _items;
  CandidateScope? _scope;
  final _hiddenSources = <TripCandidate>[];

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _done(_CandidateEntry entry) {
    _hiddenSources.addAll(entry.sources);
    setState(() {
      _items!.removeWhere(
        (item) =>
            item.sources.length == entry.sources.length &&
            item.sources.indexed.every(
              (source) => _sameCandidate(source.$2, entry.sources[source.$1]),
            ),
      );
    });
    ref.invalidate(tripsProvider);
  }

  bool _sameCandidate(TripCandidate a, TripCandidate b) =>
      a.range == b.range && listEquals(a.regionIds, b.regionIds);

  bool _isCurrent(_CandidateEntry entry, List<TripCandidate> candidates) =>
      entry.sources.every(
        (source) =>
            candidates.any((candidate) => _sameCandidate(source, candidate)),
      );

  void _reconcile(List<TripCandidate> candidates) {
    if (!mounted || _items == null) return;
    _hiddenSources.removeWhere(
      (source) =>
          !candidates.any((candidate) => _sameCandidate(source, candidate)),
    );
    final drafts = [
      for (final entry in _items!)
        if (entry.sources.length > 1 && _isCurrent(entry, candidates)) entry,
    ];
    final next = <_CandidateEntry>[];
    for (final candidate in candidates) {
      _CandidateEntry? draft;
      for (final entry in drafts) {
        if (entry.sources.any((source) => _sameCandidate(source, candidate))) {
          draft = entry;
          break;
        }
      }
      if (draft != null) {
        if (!next.contains(draft)) next.add(draft);
        continue;
      }
      if (!_hiddenSources.any((source) => _sameCandidate(source, candidate))) {
        next.add(_CandidateEntry(candidate, [candidate]));
      }
    }
    setState(() => _items = next);
  }

  // 1박 2일인데 둘째 날 사진이 없으면 후보가 갈리므로 합칠 수 있게 한다
  void _mergeWithOlder(int index, Map<String, String> names) {
    final newer = _items![index];
    final older = _items![index + 1];
    final newerCandidate = newer.candidate;
    final olderCandidate = older.candidate;
    final regionIds = [
      ...olderCandidate.regionIds,
      ...newerCandidate.regionIds.where(
        (id) => !olderCandidate.regionIds.contains(id),
      ),
    ];
    final range = DateRange(
      olderCandidate.range.start,
      newerCandidate.range.end,
    );
    setState(() {
      _items!
        ..removeAt(index + 1)
        ..[index] = _CandidateEntry(
          TripCandidate(
            range: range,
            regionIds: regionIds,
            title: candidateTitle(regionIds, range, names),
          ),
          [...older.sources, ...newer.sources],
        );
    });
  }

  Future<void> _confirm(
    _CandidateEntry entry,
    Map<String, String> names,
    CandidateScope scope,
  ) async {
    if (ref.read(candidateScopeProvider) != scope) return;
    final candidate = entry.candidate;
    final confirmation = await showTripConfirmSheet(
      context,
      title: candidate.title,
      regionIds: candidate.regionIds,
      regionNames: names,
    );
    if (confirmation == null ||
        !mounted ||
        ref.read(candidateScopeProvider) != scope) {
      return;
    }
    final List<TripCandidate> latest;
    try {
      latest = await ref.read(tripCandidatesProvider.future);
    } catch (_) {
      if (mounted) _toast('여행 후보를 새로 확인하지 못했어요. 잠시 뒤에 다시 시도해 주세요');
      return;
    }
    if (!mounted || ref.read(candidateScopeProvider) != scope) return;
    _reconcile(latest);
    if (!_isCurrent(entry, latest)) {
      _toast('이 여행 후보가 최신 기록에서 사라져 확인하지 않았어요');
      return;
    }
    final result = await ref
        .read(tripRepositoryProvider)
        .confirm(
          title: confirmation.title.isEmpty
              ? candidate.title
              : confirmation.title,
          range: candidate.range,
          regionIds: confirmation.regionIds,
          source: TripSource.auto,
        );
    if (!mounted || ref.read(candidateScopeProvider) != scope) return;
    switch (result) {
      case Ok(value: final tripId):
        _done(entry);
        await _pickPhotos(
          tripId,
          candidate.range,
          confirmation.regionIds,
          scope,
        );
      case Err(error: AppError.validation):
        _toast('이미 확인된 여행이에요');
        _done(entry);
      case Err():
        _toast('저장하지 못했어요. 잠시 뒤에 다시 시도해 주세요');
    }
  }

  // 확인 직후 내 사진을 고른다. 커플을 읽지 못하면 건너뛰고 여행 상세에서 더한다
  Future<void> _pickPhotos(
    String tripId,
    DateRange range,
    List<String> regionIds,
    CandidateScope scope,
  ) async {
    final String? coupleId;
    try {
      coupleId = (await ref.read(currentCoupleProvider.future))?.id;
    } catch (_) {
      return;
    }
    if (coupleId == null ||
        !mounted ||
        ref.read(candidateScopeProvider) != scope) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PhotoUploadPage(
          query: TripPhotoQuery(
            coupleId: coupleId!,
            tripId: tripId,
            range: range,
            regionIds: regionIds.toSet(),
          ),
        ),
      ),
    );
  }

  Future<void> _dismiss(_CandidateEntry entry, CandidateScope scope) async {
    if (ref.read(candidateScopeProvider) != scope) return;
    final candidate = entry.candidate;
    final result = await ref
        .read(tripRepositoryProvider)
        .dismiss(candidate.range);
    if (!mounted || ref.read(candidateScopeProvider) != scope) return;
    // 상대가 먼저 버렸으면(중복) 이미 처리된 것으로 본다
    if (result case Err(:final error) when error != AppError.validation) {
      _toast('처리하지 못했어요');
      return;
    }
    _done(entry);
  }

  @override
  Widget build(BuildContext context) {
    final scope = ref.watch(candidateScopeProvider);
    if (_scope != scope) {
      _scope = scope;
      _items = null;
      _hiddenSources.clear();
    }
    final candidates = ref.watch(scopedTripCandidatesProvider);
    ref.listen(scopedTripCandidatesProvider, (previous, next) {
      if (next case AsyncData(:final value)) _reconcile(value);
    });
    final names = ref.watch(regionNamesProvider).value ?? const {};
    _items ??= candidates.value
        ?.map((candidate) => _CandidateEntry(candidate, [candidate]))
        .toList();
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('함께 간 여행')),
      body: switch ((items, candidates)) {
        (final List<_CandidateEntry> items, _) when items.isEmpty =>
          const Center(child: Text('새로 찾은 여행이 없어요')),
        (final List<_CandidateEntry> items, _) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final entry = items[index];
            final c = entry.candidate;
            return Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(formatRange(c.range)),
                    const SizedBox(height: 4),
                    Text(c.regionIds.map((id) => names[id] ?? id).join(' · ')),
                    const SizedBox(height: 8),
                    _CandidatePhotos(candidate: c),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (index + 1 < items.length)
                          TextButton(
                            onPressed: () => _mergeWithOlder(index, names),
                            child: const Text('이전 후보와 합치기'),
                          ),
                        TextButton(
                          onPressed: () => _dismiss(entry, scope),
                          child: const Text('버리기'),
                        ),
                        FilledButton(
                          onPressed: () => _confirm(entry, names, scope),
                          child: const Text('확인'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        (_, AsyncValue(error: AppError.photoPermission)) => const Center(
          child: Text('사진 접근을 허용하면 함께 간 여행을 찾아드려요'),
        ),
        (_, AsyncValue(hasError: true)) => const Center(
          child: Text('여행을 찾지 못했어요'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _CandidateEntry {
  const _CandidateEntry(this.candidate, this.sources);

  final TripCandidate candidate;
  final List<TripCandidate> sources;
}

// 그 기간·조각에서 내가 찍은 사진을 가로로 보여 무슨 여행이었는지 떠올리게 한다(설계 5.4)
class _CandidatePhotos extends ConsumerWidget {
  const _CandidatePhotos({required this.candidate});

  static const shown = 10;

  final TripCandidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = [
      ...?ref
          .watch(localPhotosInRangeProvider(candidate.range))
          .value
          ?.where((p) => candidate.regionIds.contains(p.regionId)),
    ]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    if (photos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: photos.length < shown ? photos.length : shown,
            separatorBuilder: (_, _) => const SizedBox(width: 4),
            itemBuilder: (_, i) => SizedBox.square(
              dimension: 64,
              child: LocalThumbnail(assetId: photos[i].assetId),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('사진 ${photos.length}장'),
      ],
    );
  }
}
