import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/repository_providers.dart';
import '../auth/auth_state.dart';
import '../scan/home_regions.dart';
import '../scan/rescan.dart';
import '../scan/scan_providers.dart';
import '../scan/sharing_groups.dart';
import '../trip/region_picker.dart';
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

  // 사는 곳을 저장하고 같은 흐름에서 커플 지도의 생활권으로 지정한다(설계 4.4)
  Future<void> _setHome(String coupleId, String regionId) async {
    final saved = await ref
        .read(coupleRepositoryProvider)
        .setHomeRegion(regionId);
    if (saved is Ok) {
      await ref
          .read(tripRepositoryProvider)
          .setOverride(coupleId, regionId, OverrideKind.home);
    }
    ref
      ..invalidate(currentCoupleProvider)
      ..invalidate(overridesProvider);
    if (saved is Err && mounted) _toast('사는 곳을 저장하지 못했어요');
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
          if (couple != null)
            _HomeRegionCard(
              homeRegionId: couple.myHomeRegionId,
              onPick: (id) => _setHome(couple.id, id),
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

// 비교할 기록 목록에서 매일 찍히는 동네를 접으려고 사는 곳을 정한다. 아직 안 골랐으면
// 기기의 사진 기록에서 서로 다른 날이 가장 많은 조각을 추천한다(기기 밖으로 나가지 않음)
class _HomeRegionCard extends ConsumerWidget {
  const _HomeRegionCard({required this.homeRegionId, required this.onPick});

  final String? homeRegionId;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final names = ref.watch(regionNamesProvider).value ?? const {};
    final suggested = homeRegionId == null
        ? suggestHomeRegion(ref.watch(scanSnapshotProvider).value?.days ?? {})
        : null;
    Future<void> pickOther() async {
      final id = await pickRegion(context, title: '내가 사는 곳');
      if (id != null) onPick(id);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('내가 사는 곳', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              homeRegionId != null
                  ? '${names[homeRegionId] ?? homeRegionId} · 비교할 기록 맨 아래에 접어 둬요'
                  : suggested != null
                  ? '${names[suggested] ?? suggested}에서 사진을 가장 많이 찍었어요. 사는 곳으로 정할까요?'
                  : '사는 곳을 정하면 비교할 기록 맨 아래에 접어 둬요',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: pickOther,
                  child: Text(homeRegionId == null ? '직접 고르기' : '바꾸기'),
                ),
                if (suggested != null)
                  FilledButton.tonal(
                    onPressed: () => onPick(suggested),
                    child: const Text('정하기'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
