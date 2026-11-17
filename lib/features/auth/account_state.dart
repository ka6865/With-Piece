import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/repository_providers.dart';

final myDeletionDateProvider = FutureProvider.family<DateTime?, String>((
  ref,
  userId,
) async {
  if (ref.watch(sessionUserIdProvider) != userId) return null;
  return (await ref.watch(accountRepositoryProvider).myDeletionDate())
      .valueOrThrow;
});

final partnerDeletionDatesProvider =
    FutureProvider.family<List<DateTime>, String>((ref, userId) async {
      if (ref.watch(sessionUserIdProvider) != userId) return const [];
      return (await ref.watch(accountRepositoryProvider).partnerDeletionDates())
          .valueOrThrow;
    });

// 유예 중인 삭제를 알린다. 내 요청은 취소할 수 있고, 상대 요청은 사라지는 날을
// 알려 사진을 저장할 시간을 준다(설계 14.1)
class DeletionBanners extends ConsumerWidget {
  const DeletionBanners({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(sessionUserIdProvider);
    final mineState = userId == null
        ? const AsyncData<DateTime?>(null)
        : ref.watch(myDeletionDateProvider(userId));
    final mine = mineState.isLoading || mineState.hasError
        ? null
        : mineState.value;
    final partnerState = userId == null
        ? const AsyncData<List<DateTime>>([])
        : ref.watch(partnerDeletionDatesProvider(userId));
    final partner = partnerState.isLoading || partnerState.hasError
        ? const <DateTime>[]
        : partnerState.value ?? const <DateTime>[];
    String date(DateTime d) => '${d.month}월 ${d.day}일';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (mine != null)
          Card(
            child: ListTile(
              title: Text('${date(mine)}에 계정이 삭제돼요'),
              trailing: TextButton(
                onPressed: () async {
                  await ref.read(accountRepositoryProvider).cancelDeletion();
                  if (userId case final id?) {
                    ref.invalidate(myDeletionDateProvider(id));
                  }
                },
                child: const Text('삭제 취소'),
              ),
            ),
          ),
        for (final d in partner)
          Card(
            child: ListTile(
              title: Text('상대가 계정 삭제를 요청해 ${date(d)}에 함께한 기록이 사라져요'),
              trailing: TextButton(
                onPressed: () => context.push('/archive'),
                child: const Text('기록 보기'),
              ),
            ),
          ),
      ],
    );
  }
}
