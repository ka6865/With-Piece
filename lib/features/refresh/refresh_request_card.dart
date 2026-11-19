import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_state.dart';
import 'refresh_providers.dart';

// 상대가 보낸 최신화 요청을 홈 맨 위에 띄운다. "나중에"는 이 요청만 숨기고,
// 탭의 점 표시는 최신화할 때까지 남는다
class RefreshRequestCard extends ConsumerStatefulWidget {
  const RefreshRequestCard({super.key});

  @override
  ConsumerState<RefreshRequestCard> createState() => _RefreshRequestCardState();
}

class _RefreshRequestCardState extends ConsumerState<RefreshRequestCard> {
  DateTime? _dismissed;

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(receivedRefreshRequestProvider);
    if (request == null || request.requestedAt == _dismissed) {
      return const SizedBox.shrink();
    }
    final name = ref.watch(scopedCurrentCoupleProvider).value?.partnerName;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${partnerSubject(name)} 여행 최신화를 요청했어요'),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      setState(() => _dismissed = request.requestedAt),
                  child: const Text('나중에'),
                ),
                TextButton(
                  onPressed: () => context.go('/refresh'),
                  child: const Text('최신화하러 가기'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
