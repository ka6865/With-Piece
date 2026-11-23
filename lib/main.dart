import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/error_reporting.dart';
import 'data/repositories/repository_providers.dart';
import 'features/scan/scan_directory.dart';

Future<void> main() async {
  const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  // 릴리즈 빌드이고 접속값이 있을 때만 오류를 보낸다(설계 12.1)
  if (!kReleaseMode || sentryDsn.isEmpty) return _start();
  await SentryFlutter.init(
    (options) => configureSentry(
      options,
      dsn: sentryDsn,
      environment: const String.fromEnvironment(
        'SENTRY_ENVIRONMENT',
        defaultValue: 'unspecified',
      ),
    ),
    appRunner: _start,
  );
}

Future<void> _start() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  // 접속 정보 없이 조용히 기본값으로 붙지 않게 즉시 멈춘다
  if (url.isEmpty || publishableKey.isEmpty) {
    throw StateError('--dart-define-from-file=env/local.json 으로 실행해야 한다');
  }
  await Supabase.initialize(url: url, publishableKey: publishableKey);
  final prefs = await SharedPreferences.getInstance();
  // 서버 자동 동기화를 쓰던 앱의 기기별 확인 키는 더 이상 필요하지 않다.
  for (final key in prefs.getKeys()) {
    if (key == 'synced_scan' || key.startsWith('synced_scan:')) {
      await prefs.remove(key);
    }
  }
  // 로그인 여부와 무관하게 예전 백업 대상 경로를 정리한다.
  unawaited(openScanDirectory().then<void>((_) {}).catchError((Object _) {}));
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const WooriPieceApp(),
    ),
  );
}
