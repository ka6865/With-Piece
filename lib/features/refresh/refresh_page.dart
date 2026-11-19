import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/repository_providers.dart';
import '../auth/auth_state.dart';
import '../scan/rescan.dart';
import 'refresh_providers.dart';

// 여행 최신화 탭. 함께 간 곳은 두 사람이 모두 고른 기록에서만 찾아지므로, 내 최신화와
// 상대에게 보내는 요청을 한곳에 둔다(조각채우기·최신화·대표사진 설계 4.2)
class RefreshPage extends ConsumerStatefulWidget {
  const RefreshPage({super.key});

  @override
  ConsumerState<RefreshPage> createState() => _RefreshPageState();
}

class _RefreshPageState extends ConsumerState<RefreshPage> {
  bool _scanning = false;
  bool _requesting = false;

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  // 사진첩을 다시 읽은 뒤 비교할 기록을 고른다. 저장해야 최신화로 남는다
  Future<void> _refresh() async {
    setState(() => _scanning = true);
    final result = await rescanLibrary(ref);
    if (!mounted) return;
    setState(() => _scanning = false);
    switch (result) {
      case Ok():
        await context.push('/settings/photo-sharing');
      case Err(:final error):
        _toast(rescanFailureMessage(error));
    }
  }

  Future<void> _request(String? partnerName) async {
    setState(() => _requesting = true);
    final result = await ref.read(refreshRepositoryProvider).request();
    if (!mounted) return;
    setState(() => _requesting = false);
    ref.invalidate(refreshStatesProvider);
    _toast(switch (result) {
      Ok() => '${partnerTo(partnerName)} 최신화를 요청했어요',
      Err(error: AppError.validation) => '요청은 1시간에 한 번 보낼 수 있어요',
      Err() => '요청하지 못했어요. 잠시 뒤 다시 시도해 주세요',
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userId = ref.watch(sessionUserIdProvider);
    final couple = ref.watch(scopedCurrentCoupleProvider).value;
    final states = ref.watch(refreshStatesProvider).value ?? const {};
    final received = ref.watch(receivedRefreshRequestProvider);
    final now = DateTime.now();
    final partnerName = couple?.partnerName;
    final partner = couple == null ? null : states[couple.partnerId];
    final mine = states[userId];
    final canRequest =
        userId != null && canRequestRefresh(partner, userId, now);
    return Scaffold(
      appBar: AppBar(title: const Text('여행 최신화')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (received != null)
            Card(
              color: theme.colorScheme.primaryContainer,
              child: ListTile(
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text('${partnerSubject(partnerName)} 여행 최신화를 요청했어요'),
                subtitle: const Text('아래에서 최신화하면 함께 간 곳을 찾아요'),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    partnerRefreshText(partnerName, partner?.refreshedAt, now),
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: couple == null || !canRequest || _requesting
                        ? null
                        : () => _request(partnerName),
                    child: Text(
                      canRequest
                          ? '${partnerTo(partnerName)} 최신화 요청하기'
                          : '요청을 보냈어요',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('내 기록', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    mine?.refreshedAt == null
                        ? '사진을 다시 읽고 상대와 비교할 기록을 골라요'
                        : '${daysAgo(mine!.refreshedAt!, now)} 마지막으로 최신화했어요',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _scanning ? null : _refresh,
                    icon: _scanning
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_scanning ? '사진을 읽는 중' : '최신화하기'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
