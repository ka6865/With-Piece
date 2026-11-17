import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../data/repositories/repository_providers.dart';
import 'auth_state.dart';

// 사귄 날 이후의 기록으로 함께한 곳을 비교한다(설계 5.2)
class StartedOnPage extends ConsumerWidget {
  const StartedOnPage({super.key, this.isEditing = false});

  final bool isEditing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startedOn = isEditing
        ? ref.watch(currentCoupleProvider).value?.startedOn
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? '사귄 날 수정' : '사귄 날')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEditing ? '날짜를 바꿔요' : '언제부터 함께였나요?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('이날 이후의 기록 중 각자가 비교를 승인한 날짜와 지역으로 함께 간 곳을 찾아요.'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final today = DateTime.now();
                final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime(1950),
                  lastDate: today,
                  initialDate: startedOn ?? today,
                );
                if (date == null) return;
                final result = await ref
                    .read(coupleRepositoryProvider)
                    .setStartedOn(date);
                if (result is Err && context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('저장하지 못했어요')));
                  return;
                }
                ref.invalidate(currentCoupleProvider);
              },
              child: Text(isEditing ? '날짜 바꾸기' : '날짜 고르기'),
            ),
          ],
        ),
      ),
    );
  }
}
