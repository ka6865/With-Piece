import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../data/repositories/repository_providers.dart';

final myDeletionDateProvider = FutureProvider<DateTime?>(
  (ref) async => (await ref.watch(accountRepositoryProvider).myDeletionDate())
      .valueOrThrow,
);

final partnerDeletionDatesProvider = FutureProvider<List<DateTime>>(
  (ref) async =>
      (await ref.watch(accountRepositoryProvider).partnerDeletionDates())
          .valueOrThrow,
);

// 유예 중인 삭제를 알린다. 내 요청은 취소할 수 있고, 상대 요청은 사라지는 날을
// 알려 사진을 저장할 시간을 준다(설계 14.1)
class DeletionBanners extends ConsumerWidget {
  const DeletionBanners({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myDeletionDateProvider).value;
    final partner = ref.watch(partnerDeletionDatesProvider).value ?? const [];
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
                  ref.invalidate(myDeletionDateProvider);
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
