import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show UserIdentity;

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/repository_providers.dart';
import 'account_state.dart';
import 'auth_state.dart';
import 'login_page.dart';
import '../scan/rescan.dart';
import '../scan/scan_providers.dart';
import '../scan/scanner.dart';

// 여러 로그인 방법을 한 계정에 묶는다. Kakao는 이메일이 없어 자동 연동되지 않는다(설계 10.2)
class AccountLinksPage extends ConsumerStatefulWidget {
  const AccountLinksPage({super.key});

  @override
  ConsumerState<AccountLinksPage> createState() => _AccountLinksPageState();
}

class _AccountLinksPageState extends ConsumerState<AccountLinksPage> {
  var _rescanning = false;

  Future<void> _rescan() async {
    if (_rescanning) return;
    setState(() => _rescanning = true);
    Result<void> result = const Err<void>(AppError.unknown);
    try {
      result = await rescan(
        Scanner(
          ref.read(photoLibraryRepositoryProvider),
          await ref.read(regionLocatorProvider.future),
          await ref.read(scanStoreProvider.future),
        ),
        () => ref
          ..invalidate(scanSnapshotProvider)
          ..invalidate(photoDaysSyncedProvider),
      );
    } catch (_) {
      result = const Err(AppError.unknown);
    } finally {
      if (mounted) setState(() => _rescanning = false);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result is Ok
              ? '사진 기록을 다시 확인했어요'
              : result is Err && result.error == AppError.photoPermission
              ? '사진 전체 접근을 허용한 뒤 다시 시도해 주세요'
              : '다시 스캔하지 못했어요. 잠시 뒤 다시 시도해 주세요',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authRepositoryProvider);
    final userId = ref.watch(sessionUserIdProvider);
    final identities = userId == null
        ? const AsyncLoading<List<UserIdentity>>()
        : ref.watch(identitiesProvider(userId));
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
            if (ref.watch(currentCoupleProvider).value != null) ...[
              ListTile(
                title: const Text('사귄 날 수정'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/started-on?edit=true'),
              ),
              ListTile(
                title: const Text('비교할 기록 선택'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/settings/photo-sharing'),
              ),
            ],
            ListTile(
              title: const Text('전체 다시 스캔'),
              trailing: _rescanning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              onTap: _rescanning ? null : _rescan,
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
                final result = await ref
                    .read(accountRepositoryProvider)
                    .requestDeletion();
                toastOnError(result);
                if (result is Ok) {
                  final userId = ref.read(sessionProvider).value?.user.id;
                  if (userId != null) {
                    await ref.read(scanSyncProvider).clearForUser(userId);
                    ref
                      ..invalidate(scanSnapshotProvider)
                      ..invalidate(photoDaysSyncedProvider);
                  }
                }
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
