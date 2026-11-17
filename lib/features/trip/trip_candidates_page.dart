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
  List<TripCandidate>? _items;

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  void _done(TripCandidate candidate) {
    setState(() => _items!.remove(candidate));
    ref.invalidate(tripsProvider);
  }

  // 1박 2일인데 둘째 날 사진이 없으면 후보가 갈리므로 합칠 수 있게 한다
  void _mergeWithOlder(int index, Map<String, String> names) {
    final newer = _items![index];
    final older = _items![index + 1];
    final regionIds = [
      ...older.regionIds,
      ...newer.regionIds.where((id) => !older.regionIds.contains(id)),
    ];
    final range = DateRange(older.range.start, newer.range.end);
    setState(() {
      _items!
        ..removeAt(index + 1)
        ..[index] = TripCandidate(
          range: range,
          regionIds: regionIds,
          title: candidateTitle(regionIds, range, names),
        );
    });
  }

  Future<void> _confirm(
    TripCandidate candidate,
    Map<String, String> names,
  ) async {
    final confirmation = await showTripConfirmSheet(
      context,
      title: candidate.title,
      regionIds: candidate.regionIds,
      regionNames: names,
    );
    if (confirmation == null || !mounted) return;
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
    if (!mounted) return;
    switch (result) {
      case Ok(value: final tripId):
        _done(candidate);
        await _pickPhotos(tripId, candidate.range, confirmation.regionIds);
      case Err(error: AppError.validation):
        _toast('이미 확인된 여행이에요');
        _done(candidate);
      case Err():
        _toast('저장하지 못했어요. 잠시 뒤에 다시 시도해 주세요');
    }
  }

  // 확인 직후 내 사진을 고른다. 커플을 읽지 못하면 건너뛰고 여행 상세에서 더한다
  Future<void> _pickPhotos(
    String tripId,
    DateRange range,
    List<String> regionIds,
  ) async {
    final String? coupleId;
    try {
      coupleId = (await ref.read(currentCoupleProvider.future))?.id;
    } catch (_) {
      return;
    }
    if (coupleId == null || !mounted) return;
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

  Future<void> _dismiss(TripCandidate candidate) async {
    final result = await ref
        .read(tripRepositoryProvider)
        .dismiss(candidate.range);
    if (!mounted) return;
    // 상대가 먼저 버렸으면(중복) 이미 처리된 것으로 본다
    if (result case Err(:final error) when error != AppError.validation) {
      _toast('처리하지 못했어요');
      return;
    }
    _done(candidate);
  }

  @override
  Widget build(BuildContext context) {
    final candidates = ref.watch(tripCandidatesProvider);
    final names = ref.watch(regionNamesProvider).value ?? const {};
    _items ??= candidates.value?.toList();
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('함께 간 여행')),
      body: switch ((items, candidates)) {
        (final List<TripCandidate> items, _) when items.isEmpty => const Center(
          child: Text('새로 찾은 여행이 없어요'),
        ),
        (final List<TripCandidate> items, _) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final c = items[index];
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
                          onPressed: () => _dismiss(c),
                          child: const Text('버리기'),
                        ),
                        FilledButton(
                          onPressed: () => _confirm(c, names),
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
