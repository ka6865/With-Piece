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
import '../guide/guide.dart';

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
  void initState() {
    super.initState();
    // 처음 연결 화면에 온 사람에게 소개 카드를 한 번 보여준다(2026-11-23 설계 ④)
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getBool(IntroPage.seenKey) != true) {
      prefs.setBool(IntroPage.seenKey, true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openIntro();
      });
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _openIntro() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const IntroPage()));

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

  // 코드를 누군가에게 잘못 알렸을 때 옛 코드를 바로 무효로 만든다
  Future<void> _regenerateInvite() async {
    final result = await ref.read(coupleRepositoryProvider).regenerateInvite();
    if (!mounted) return;
    _toast(result is Err ? '새 코드를 받지 못했어요' : '새 코드를 받았어요. 이전 코드는 더 이상 쓸 수 없어요');
    ref.invalidate(myInviteProvider);
  }

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(sessionUserIdProvider);
    final invite = userId == null
        ? const AsyncLoading<Invite?>()
        : ref.watch(myInviteProvider(userId));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('연인과 연결하기'),
        actions: [
          IconButton(
            tooltip: '소개 보기',
            icon: const Icon(Icons.help_outline),
            onPressed: _openIntro,
          ),
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
          const SizedBox(height: 16),
          const _MeetingPieces(),
          const SizedBox(height: 16),
          // 두 사람이 각자 하는 일을 카드 둘로 나눈다. 내 코드를 보내거나, 받은 코드를 넣는다
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('내 초대 코드', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  switch (invite) {
                    AsyncData(value: final Invite invite) => Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            invite.code,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: '복사',
                          icon: const Icon(Icons.copy),
                          onPressed: () => Clipboard.setData(
                            ClipboardData(text: invite.code),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: '새 코드 받기',
                          icon: const Icon(Icons.refresh),
                          onPressed: _regenerateInvite,
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
                  const SizedBox(height: 8),
                  Text(
                    '코드는 만든 뒤 3일 동안 한 번만 쓸 수 있어요. '
                    '연결하거나 끊으면 남은 코드는 사라져요.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('받은 코드 입력', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.none,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _join, child: const Text('연결하기')),
                ],
              ),
            ),
          ),
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
          const SizedBox(height: 12),
          const Text('새로 연결하면 지난 기록은 아카이브에 남고, 새 커플에서는 사진 기록 공유를 다시 허용해야 해요.'),
        ],
      ),
    );
  }
}

// 두 조각이 서로를 향해 맞물리려는 모습. 연결 전이라 아직 떨어져 있다(커플 디자인 4.6)
class _MeetingPieces extends StatelessWidget {
  const _MeetingPieces();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.rotate(
            angle: -0.2,
            child: Icon(Icons.extension, size: 56, color: scheme.secondary),
          ),
          const SizedBox(width: 8),
          Transform.rotate(
            angle: 0.2,
            child: Icon(
              Icons.extension_outlined,
              size: 56,
              color: scheme.tertiary,
            ),
          ),
        ],
      ),
    );
  }
}
