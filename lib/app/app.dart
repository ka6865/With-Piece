import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class WooriPieceApp extends ConsumerWidget {
  const WooriPieceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: '우리들의 조각',
    theme: lightTheme,
    darkTheme: darkTheme,
    themeMode: ThemeMode.system,
    routerConfig: ref.watch(routerProvider),
  );
}
