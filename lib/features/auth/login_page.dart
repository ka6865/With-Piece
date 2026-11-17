import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/repository_providers.dart';

final providerLabels = {
  OAuthProvider.kakao: '카카오',
  OAuthProvider.apple: 'Apple',
  OAuthProvider.google: 'Google',
};

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authRepositoryProvider);
    final last = auth.lastProvider;
    // 계정이 갈라지지 않게 마지막으로 쓴 방법을 맨 위에 둔다(설계 10.2)
    final providers = [
      ...AuthRepository.providers.where((p) => p == last),
      ...AuthRepository.providers.where((p) => p != last),
    ];
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '우리들의 조각',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text('함께 다녀온 곳을 퍼즐로 채워요', textAlign: TextAlign.center),
              const SizedBox(height: 48),
              for (final provider in providers) ...[
                FilledButton(
                  onPressed: () async {
                    final result = await auth.signIn(provider);
                    if (result is Err && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('로그인하지 못했어요')),
                      );
                    }
                  },
                  child: Text('${providerLabels[provider]}로 시작하기'),
                ),
                if (provider == last)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('최근에 사용한 방법', textAlign: TextAlign.center),
                  ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
