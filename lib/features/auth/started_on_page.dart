import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/couple_repository.dart';
import '../../data/repositories/repository_providers.dart';
import 'auth_state.dart';

// 사귄 날 이후의 기록으로 함께한 곳을 비교한다(설계 5.2)
class StartedOnPage extends ConsumerStatefulWidget {
  const StartedOnPage({super.key, this.isEditing = false});

  final bool isEditing;

  @override
  ConsumerState<StartedOnPage> createState() => _StartedOnPageState();
}

class _StartedOnPageState extends ConsumerState<StartedOnPage> {
  // 재조회를 기다리는 동안 다시 눌러 저장이 두 번 나가지 않게 한다
  bool _busy = false;

  Future<void> _guard(Future<void> Function() run) async {
    setState(() => _busy = true);
    try {
      await run();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.isEditing;
    final couple = ref.watch(currentCoupleProvider).value;
    final startedOn = isEditing ? couple?.startedOn : null;
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
              onPressed: _busy
                  ? null
                  : () => _guard(() async {
                      final userId = ref.read(sessionUserIdProvider);
                      final coupleId = couple?.id;
                      bool sameScope() =>
                          context.mounted &&
                          (ModalRoute.of(context)?.isCurrent ?? true) &&
                          ref.read(sessionUserIdProvider) == userId &&
                          ref.read(currentCoupleProvider).value?.id == coupleId;
                      void failed() =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('저장하지 못했어요')),
                          );
                      // Realtime이 커플을 다시 읽는 중이면 끝날 때까지 기다린 값으로 비교한다.
                      // 실패하면 .future는 자동 재시도 동안 끝나지 않으므로 상태를 지켜본다
                      Future<(bool, DateTime?)> latestStartedOn() async {
                        bool settled(AsyncValue<Couple?> v) =>
                            !v.isLoading || v.hasError;
                        var couple = ref.read(currentCoupleProvider);
                        if (!settled(couple)) {
                          final done = Completer<AsyncValue<Couple?>>();
                          final sub = ref.listenManual(currentCoupleProvider, (
                            _,
                            next,
                          ) {
                            if (settled(next) && !done.isCompleted) {
                              done.complete(next);
                            }
                          });
                          // 응답이 오지 않으면 버튼이 막힌 채 남으므로 실패로 본다
                          couple = await done.future.timeout(
                            const Duration(seconds: 10),
                            onTimeout: () => AsyncError(
                              TimeoutException(null),
                              StackTrace.current,
                            ),
                          );
                          sub.close();
                        }
                        return (!couple.hasError, couple.value?.startedOn);
                      }

                      final today = DateTime.now();
                      final date = await showDatePicker(
                        context: context,
                        firstDate: DateTime(1950),
                        lastDate: today,
                        initialDate: startedOn ?? today,
                      );
                      if (date == null || !context.mounted || !sameScope()) {
                        return;
                      }
                      final (loaded, currentDate) = await latestStartedOn();
                      if (!context.mounted || !sameScope()) return;
                      if (!loaded) return failed();
                      if (isEditing &&
                          currentDate != null &&
                          date.isAfter(currentDate)) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('사귄 날을 늦출까요?'),
                            content: const Text(
                              '동기화하면 두 사람의 새 날짜 이전 스캔 기록과 비교 승인이 삭제돼요. '
                              '삭제된 비교 승인은 날짜를 다시 앞당겨도 다시 선택해야 해요.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('취소'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text('변경하기'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true ||
                            !context.mounted ||
                            !sameScope()) {
                          return;
                        }
                        final (reloaded, latest) = await latestStartedOn();
                        if (!context.mounted || !sameScope()) return;
                        if (!reloaded) return failed();
                        if (latest != currentDate) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('사귄 날이 방금 바뀌었어요. 확인 후 다시 골라 주세요'),
                            ),
                          );
                          return;
                        }
                      }
                      final result = await ref
                          .read(coupleRepositoryProvider)
                          .setStartedOn(date);
                      if (!context.mounted || !sameScope()) return;
                      if (result is Err) return failed();
                      ref.invalidate(currentCoupleProvider);
                      if (isEditing) {
                        final router = GoRouter.maybeOf(context);
                        if (router != null && router.canPop()) {
                          router.pop();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('사귄 날을 저장했어요')),
                          );
                        }
                      }
                    }),
              child: Text(isEditing ? '날짜 바꾸기' : '날짜 고르기'),
            ),
          ],
        ),
      ),
    );
  }
}
