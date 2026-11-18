import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/auth_state.dart';

// 하단 탭(홈·지도·앨범·설정). 탭마다 자기 화면 상태를 유지한다. 커플이 아닌 단계에서는
// 홈·지도·앨범이 의미가 없으므로 탭을 숨긴다(커플 디자인 4.3). 커플 조회 실패(오프라인)
// 때는 번들 지도로 갈 수 있게 탭을 남긴다(설계 12장)
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showTabs = switch (ref.watch(appStageProvider)) {
      AppStage.ready || AppStage.unavailable => true,
      _ => false,
    };
    return Scaffold(
      body: shell,
      bottomNavigationBar: showTabs
          ? NavigationBar(
              selectedIndex: shell.currentIndex,
              // 지금 탭을 다시 누르면 그 탭의 첫 화면으로 돌아간다
              onDestinationSelected: (index) => shell.goBranch(
                index,
                initialLocation: index == shell.currentIndex,
              ),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.favorite_border),
                  selectedIcon: Icon(Icons.favorite),
                  label: '홈',
                ),
                NavigationDestination(
                  icon: Icon(Icons.map_outlined),
                  selectedIcon: Icon(Icons.map),
                  label: '지도',
                ),
                NavigationDestination(
                  icon: Icon(Icons.photo_album_outlined),
                  selectedIcon: Icon(Icons.photo_album),
                  label: '앨범',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: '설정',
                ),
              ],
            )
          : null,
    );
  }
}
