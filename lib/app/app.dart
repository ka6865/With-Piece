import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/scan/realtime_sync.dart';
import 'router.dart';
import 'theme.dart';

class WooriPieceApp extends ConsumerWidget {
  const WooriPieceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(realtimeSyncProvider);
    return MaterialApp.router(
      title: '우리들의 조각',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      // 한국어 전용 앱이라 기기 언어와 상관없이 달력·버튼 문구를 한국어로 둔다
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
