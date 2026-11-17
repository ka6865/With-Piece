import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'album_providers.dart';

// 아카이브된 커플 목록. 상대가 계정 삭제를 요청했으면 기록이 사라지는 날을 알린다(설계 14장)
class ArchivePage extends ConsumerWidget {
  const ArchivePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final couples = ref.watch(archivedCouplesProvider);
    String date(DateTime d) => '${d.year}.${d.month}.${d.day}';
    return Scaffold(
      appBar: AppBar(title: const Text('지난 기록')),
      body: switch (couples) {
        AsyncValue(value: final List<dynamic> list) when list.isEmpty =>
          const Center(child: Text('지난 기록이 없어요')),
        AsyncValue(hasValue: true) => ListView(
          children: [
            for (final c in couples.value!)
              ListTile(
                title: Text(c.partnerName),
                subtitle: Text(
                  c.partnerDeletionDate == null
                      ? '${date(c.archivedAt)}에 연결이 끊겼어요'
                      : '${c.partnerDeletionDate!.month}월 '
                            '${c.partnerDeletionDate!.day}일에 사라져요',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/archive/${c.id}'),
              ),
          ],
        ),
        AsyncValue(hasError: true) => const Center(
          child: Text('지난 기록을 불러오지 못했어요'),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
