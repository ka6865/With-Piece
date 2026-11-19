import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/photo_sharing_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../auth/auth_state.dart';
import '../refresh/refresh_providers.dart';
import 'photo_days.dart';
import 'scan_providers.dart';
import 'trip_candidates.dart';

class PhotoSharingChoices {
  const PhotoSharingChoices({
    required this.coupleId,
    required this.days,
    required this.approved,
    required this.names,
  });
  final String coupleId;
  final Map<PhotoDay, int> days;
  final Set<PhotoDay> approved;
  final Map<String, String> names;
}

final photoSharingRepositoryProvider = Provider<PhotoSharingRepository>(
  (ref) => PhotoSharingRepository(ref.watch(supabaseClientProvider)),
);

final photoSharingChoicesProvider = FutureProvider<PhotoSharingChoices>((
  ref,
) async {
  ref.watch(sessionUserIdProvider);
  final couple = await ref.watch(currentCoupleProvider.future);
  if (couple == null || couple.startedOn == null) throw AppError.validation;
  await ref.watch(photoDaysSyncedProvider.future);
  final snapshot = await ref.watch(scanSnapshotProvider.future);
  final approved =
      (await ref
              .watch(photoSharingRepositoryProvider)
              .approvedWithCounts(couple.id))
          .valueOrThrow;
  approved.removeWhere((day, _) => day.day.isBefore(couple.startedOn!));
  return PhotoSharingChoices(
    coupleId: couple.id,
    days: {
      ...approved,
      for (final entry in snapshot.days.entries)
        if (!entry.key.day.isBefore(couple.startedOn!)) entry.key: entry.value,
    },
    approved: approved.keys.toSet(),
    names: await ref.watch(regionNamesProvider.future),
  );
});

final savePhotoSharingProvider =
    Provider<
      Future<Result<void>> Function(PhotoSharingChoices, Map<PhotoDay, bool>)
    >(
      (ref) => (choices, changes) async {
        final result = await ref
            .read(photoSharingRepositoryProvider)
            .update(
              choices.coupleId,
              approve: {
                // 재조회로 목록에서 빠진 날짜(사귄 날 이전 등)는 승인할 수 없다
                for (final entry in changes.entries)
                  if (entry.value && choices.days.containsKey(entry.key))
                    entry.key: choices.days[entry.key]!,
              },
              revoke: {
                for (final entry in changes.entries)
                  if (!entry.value) entry.key,
              },
            );
        if (result is Ok) {
          ref.invalidate(photoSharingChoicesProvider);
          ref.invalidate(matchedDaysProvider);
          // 저장이 곧 최신화다. 실패해도 저장은 끝났으므로 결과를 바꾸지 않고
          // 다음 저장 때 다시 남긴다
          await ref.read(refreshRepositoryProvider).markRefreshed();
          ref.invalidate(refreshStatesProvider);
        }
        return result;
      },
    );

// 선택한 날짜·지역만 비교에 쓴다. 처음에는 아무것도 선택하지 않는다.
class PhotoSharingPage extends ConsumerStatefulWidget {
  const PhotoSharingPage({super.key});
  @override
  ConsumerState<PhotoSharingPage> createState() => _PhotoSharingPageState();
}

class _PhotoSharingPageState extends ConsumerState<PhotoSharingPage> {
  final _changes = <PhotoDay, bool>{};
  String? _coupleId;
  String? _userId;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(sessionUserIdProvider);
    if (_userId != userId) {
      _userId = userId;
      _changes.clear();
      _saving = false;
      _error = null;
    }
    final choices = ref.watch(photoSharingChoicesProvider);
    final data = choices.isLoading || choices.hasError ? null : choices.value;
    if (data != null && _coupleId != data.coupleId) {
      _coupleId = data.coupleId;
      _changes.clear();
      _saving = false;
      _error = null;
    }
    final days = data?.days.keys.toList() ?? <PhotoDay>[];
    days.sort((a, b) {
      final date = b.day.compareTo(a.day);
      return date == 0 ? a.regionId.compareTo(b.regionId) : date;
    });
    return Scaffold(
      appBar: AppBar(title: const Text('비교할 기록 선택')),
      body: data == null
          ? Center(
              child: choices.hasError
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('기록을 불러오지 못했어요. 사진 전체 접근과 연결 상태를 확인해 주세요.'),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(photoSharingChoicesProvider),
                          child: const Text('다시 시도'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '함께 비교해도 되는 날짜와 지역만 골라 주세요.\n'
                    '승인한 날짜와 지역은 상대가 알아낼 수 있어요. 선택하지 않은 기록은 비교하지 않아요. '
                    '승인은 현재 커플에만 적용돼요.',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_error!),
                  ),
                if (days.isEmpty)
                  const Expanded(child: Center(child: Text('비교할 사진 기록이 없어요')))
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: days.length,
                      itemBuilder: (context, index) {
                        final day = days[index];
                        return CheckboxListTile(
                          value: _changes[day] ?? data.approved.contains(day),
                          title: Text(data.names[day.regionId] ?? day.regionId),
                          subtitle: Text(
                            '${day.day.year}.${day.day.month}.${day.day.day} · 사진 ${data.days[day]}장',
                          ),
                          onChanged: _saving
                              ? null
                              : (checked) => setState(() {
                                  final selected = checked == true;
                                  _changes[day] = selected;
                                }),
                        );
                      },
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: data == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _saving
                      ? null
                      : () async {
                          setState(() {
                            _saving = true;
                            _error = null;
                          });
                          // 결과 문구용. 후보를 읽지 못해도 저장은 막지 않는다
                          List<TripCandidate>? before;
                          try {
                            before = ref.read(tripCandidatesProvider).value;
                          } catch (_) {
                            before = null;
                          }
                          final result = await ref.read(
                            savePhotoSharingProvider,
                          )(data, Map.of(_changes));
                          if (!context.mounted ||
                              _userId != userId ||
                              _coupleId != data.coupleId) {
                            return;
                          }
                          setState(() {
                            _saving = false;
                          });
                          if (result is Err) {
                            setState(
                              () =>
                                  _error = '저장하지 못했어요. 선택은 그대로예요. 다시 시도해 주세요.',
                            );
                            return;
                          }
                          setState(() {
                            _changes.clear();
                          });
                          final messenger = ScaffoldMessenger.of(context);
                          final router = GoRouter.maybeOf(context);
                          int? found;
                          try {
                            found = newCandidateCount(
                              before,
                              await ref.read(tripCandidatesProvider.future),
                            );
                          } catch (_) {
                            found = null;
                          }
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(sharingSavedMessage(found)),
                              action: router != null && (found ?? 0) > 0
                                  ? SnackBarAction(
                                      label: '보기',
                                      onPressed: () =>
                                          router.push('/trips/candidates'),
                                    )
                                  : null,
                            ),
                          );
                        },
                  child: Text(_saving ? '저장 중' : '비교 범위 저장'),
                ),
              ),
            ),
    );
  }
}
