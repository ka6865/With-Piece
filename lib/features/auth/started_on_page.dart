import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../data/repositories/repository_providers.dart';
import 'auth_state.dart';

// 사귄 날 이후의 사진만 비교한다(설계 5.2)
class StartedOnPage extends ConsumerWidget {
  const StartedOnPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('사귄 날')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('언제부터 함께였나요?', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('이날 이후 두 사람이 같은 날 같은 곳에서 찍은 사진으로 지도를 채워요.'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              final today = DateTime.now();
              final date = await showDatePicker(
                context: context,
                firstDate: DateTime(1950),
                lastDate: today,
                initialDate: today,
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
            child: const Text('날짜 고르기'),
          ),
        ],
      ),
    ),
  );
}
