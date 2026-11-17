import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'data/repositories/repository_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  // 접속 정보 없이 조용히 기본값으로 붙지 않게 즉시 멈춘다
  if (url.isEmpty || publishableKey.isEmpty) {
    throw StateError('--dart-define-from-file=env/local.json 으로 실행해야 한다');
  }
  await Supabase.initialize(url: url, publishableKey: publishableKey);
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const WooriPieceApp(),
    ),
  );
}
