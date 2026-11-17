import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/photo_sharing_repository.dart';
import '../auth/auth_state.dart';
import 'photo_days.dart';
import 'scan_providers.dart';

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
  return PhotoSharingChoices(
    coupleId: couple.id,
    days: {
      for (final entry in snapshot.days.entries)
        if (!entry.key.day.isBefore(couple.startedOn!)) entry.key: entry.value,
    },
    approved:
        (await ref.watch(photoSharingRepositoryProvider).approved(couple.id))
            .valueOrThrow,
    names: await ref.watch(regionNamesProvider.future),
  );
});

final savePhotoSharingProvider =
    Provider<Future<Result<void>> Function(String, Set<PhotoDay>)>(
      (ref) => (coupleId, days) async {
        final result = await ref
            .read(photoSharingRepositoryProvider)
            .replace(coupleId, days);
        if (result is Ok) {
          ref.invalidate(photoSharingChoicesProvider);
          ref.invalidate(matchedDaysProvider);
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
  Set<PhotoDay>? _selected;
  String? _coupleId;
  String? _userId;
  bool _saving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(sessionUserIdProvider);
    if (_userId != userId) {
      _userId = userId;
      _selected = null;
      _error = null;
    }
    final choices = ref.watch(photoSharingChoicesProvider);
    final data = choices.isLoading || choices.hasError ? null : choices.value;
    if (data != null && (_selected == null || _coupleId != data.coupleId)) {
      _coupleId = data.coupleId;
      _selected = data.approved.intersection(data.days.keys.toSet());
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
                          value: _selected!.contains(day),
                          title: Text(data.names[day.regionId] ?? day.regionId),
                          subtitle: Text(
                            '${day.day.year}.${day.day.month}.${day.day.day} · 사진 ${data.days[day]}장',
                          ),
                          onChanged: _saving
                              ? null
                              : (checked) => setState(() {
                                  checked == true
                                      ? _selected!.add(day)
                                      : _selected!.remove(day);
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
                          final result = await ref.read(
                            savePhotoSharingProvider,
                          )(data.coupleId, Set.of(_selected!));
                          if (!context.mounted) return;
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
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('비교할 기록을 저장했어요')),
                          );
                        },
                  child: Text(_saving ? '저장 중' : '비교 범위 저장'),
                ),
              ),
            ),
    );
  }
}
