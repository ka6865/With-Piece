import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/dev_flags.dart';
import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/couple_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../scan/solo_preview.dart';
import 'account_state.dart';
import 'auth_state.dart';

const _outcomeMessages = {
  JoinOutcome.invalidCode: '코드를 다시 확인해 주세요',
  JoinOutcome.expired: '만료되었거나 이미 쓴 코드예요',
  JoinOutcome.self: '내 코드는 내가 쓸 수 없어요',
  JoinOutcome.alreadyCoupled: '이미 다른 사람과 연결되어 있어요',
  JoinOutcome.rateLimited: '잠시 뒤에 다시 시도해 주세요',
  JoinOutcome.deletionPending: '계정 삭제를 취소한 뒤 연결해 주세요',
};

class InvitePage extends ConsumerStatefulWidget {
  const InvitePage({super.key});

  @override
  ConsumerState<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends ConsumerState<InvitePage> {
  late final _code = TextEditingController(
    text: ref.read(pendingInviteCodeProvider),
  );

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _join() async {
    final code = _code.text.trim();
    final couples = ref.read(coupleRepositoryProvider);
    final result =
        ref.read(devSoloEnabledProvider) && code.toUpperCase() == devSoloCode
        ? await couples.joinDevSolo()
        : await couples.join(code);
    if (!mounted) return;
    switch (result) {
      case Ok(value: JoinOutcome.joined):
        ref.read(pendingInviteCodeProvider.notifier).set(null);
        ref.invalidate(currentCoupleProvider);
      case Ok(:final value):
        _toast(_outcomeMessages[value]!);
      case Err():
        _toast('연결하지 못했어요. 잠시 뒤에 다시 시도해 주세요');
    }
  }

  Future<void> _createInvite() async {
    final result = await ref.read(coupleRepositoryProvider).createInvite();
    if (!mounted) return;
    if (result is Err) _toast('초대 코드를 만들지 못했어요');
    ref.invalidate(myInviteProvider);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(sessionUserIdProvider);
    final invite = userId == null
        ? const AsyncLoading<Invite?>()
        : ref.watch(myInviteProvider(userId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('연인과 연결하기'),
        actions: [
          TextButton(
            onPressed: () => context.push('/settings/accounts'),
            child: const Text('계정 설정'),
          ),
          TextButton(
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
            child: const Text('로그아웃'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const DeletionBanners(),
          const SoloPreview(),
          const SizedBox(height: 24),
          Text('내 초대 코드', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          switch (invite) {
            AsyncData(value: final Invite invite) => Row(
              children: [
                Expanded(
                  child: SelectableText(
                    invite.code,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: '복사',
                  icon: const Icon(Icons.copy),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: invite.code)),
                ),
              ],
            ),
            AsyncData() => OutlinedButton(
              onPressed: _createInvite,
              child: const Text('초대 코드 만들기'),
            ),
            AsyncError() => const Text('초대 코드를 불러오지 못했어요'),
            _ => const LinearProgressIndicator(),
          },
          const SizedBox(height: 32),
          Text('받은 코드 입력', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.none,
            autocorrect: false,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _join, child: const Text('연결하기')),
          const SizedBox(height: 32),
          ListTile(
            title: const Text('지난 기록'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/archive'),
          ),
          // 계정이 갈라진 사용자가 원인을 알 수 있게 한다(설계 10.2)
          const Text(
            '이미 연인과 연결했다면 다른 방법으로 로그인했을 수 있어요. '
            '로그아웃한 뒤 처음에 썼던 방법으로 다시 로그인해 보세요.',
          ),
        ],
      ),
    );
  }
}
