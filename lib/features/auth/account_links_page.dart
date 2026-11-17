import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/result/result.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/repository_providers.dart';
import 'account_state.dart';
import 'auth_state.dart';
import 'login_page.dart';

// 여러 로그인 방법을 한 계정에 묶는다. Kakao는 이메일이 없어 자동 연동되지 않는다(설계 10.2)
class AccountLinksPage extends ConsumerWidget {
  const AccountLinksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authRepositoryProvider);
    final identities = ref.watch(identitiesProvider);
    void toastOnError(Result<void> result) {
      if (result is Err && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('처리하지 못했어요')));
      }
      ref.invalidate(identitiesProvider);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('계정 연결')),
      body: switch (identities) {
        AsyncData(:final value) => ListView(
          children: [
            for (final identity in value)
              ListTile(
                title: Text(
                  providerLabels.entries
                          .where((e) => e.key.name == identity.provider)
                          .firstOrNull
                          ?.value ??
                      identity.provider,
                ),
                trailing: TextButton(
                  // 마지막 로그인 수단은 끊지 않는다
                  onPressed: value.length < 2
                      ? null
                      : () async => toastOnError(await auth.unlink(identity)),
                  child: const Text('연결 해제'),
                ),
              ),
            for (final provider in AuthRepository.providers)
              if (!value.any((i) => i.provider == provider.name))
                ListTile(
                  title: Text('${providerLabels[provider]} 연결'),
                  trailing: const Icon(Icons.add_link),
                  onTap: () async => toastOnError(await auth.link(provider)),
                ),
            const Divider(),
            if (ref.watch(currentCoupleProvider).value != null)
              ListTile(
                title: const Text('커플 연결 끊기'),
                onTap: () async {
                  if (!await _confirmUnlink(context)) return;
                  toastOnError(
                    await ref.read(coupleRepositoryProvider).archive(),
                  );
                  ref.invalidate(currentCoupleProvider);
                },
              ),
            ListTile(
              title: const Text('지난 기록'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/archive'),
            ),
            ListTile(title: const Text('로그아웃'), onTap: () => auth.signOut()),
            ListTile(
              title: Text(
                '계정 삭제',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () async {
                if (!await _confirmDeletion(context)) return;
                toastOnError(
                  await ref.read(accountRepositoryProvider).requestDeletion(),
                );
                ref
                  ..invalidate(currentCoupleProvider)
                  ..invalidate(myDeletionDateProvider);
              },
            ),
          ],
        ),
        AsyncError() => const Center(child: Text('연결 정보를 불러오지 못했어요')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

// 결과를 그대로 적고 확인받는다. 상대 화면의 기록도 함께 사라진다(설계 14.1)
Future<bool> _confirmDeletion(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('계정을 삭제할까요?'),
        content: const Text(
          '지금 커플 연결이 끊기고 내 위치 기록은 바로 지워져요. '
          '30일 뒤에는 함께한 여행과 사진이 상대 화면에서도 사라져요. '
          '그 전에 다시 로그인하면 삭제를 취소할 수 있어요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제 요청'),
          ),
        ],
      ),
    ) ??
    false;

// 기록은 지우지 않고 아카이브한다. 한쪽이 상대의 기록까지 없애지 못하게 하려는 것이다(설계 14장)
Future<bool> _confirmUnlink(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('커플 연결을 끊을까요?'),
        content: const Text(
          '두 사람 모두 새 기록을 남길 수 없게 돼요. 함께한 여행과 사진은 지우지 않고 '
          '설정의 지난 기록에서 계속 볼 수 있어요. 다시 이어지려면 새로 초대해야 해요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('연결 끊기'),
          ),
        ],
      ),
    ) ??
    false;
