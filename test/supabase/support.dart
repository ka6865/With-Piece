import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

// 로컬 스택(supabase start) 대상 테스트의 공용 도구. 스택이 없으면 건너뛴다.
// 앱에는 이메일 로그인이 없고, 테스트 사용자를 만들 때만 쓴다
final _envFile = File('env/local.json');
final _env = _envFile.existsSync()
    ? jsonDecode(_envFile.readAsStringSync()) as Map<String, dynamic>
    : const <String, dynamic>{};

// 건너뛸 이유. 스택에 닿으면 null
Future<String?> localStackSkipReason() async {
  final url = _env['SUPABASE_URL'] as String?;
  if (url == null) return 'env/local.json이 없다';
  final uri = Uri.parse(url);
  if (!const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host)) {
    return '통합 테스트는 로컬 Supabase 주소만 허용한다';
  }
  try {
    final socket = await Socket.connect(
      uri.host,
      uri.port,
      timeout: const Duration(seconds: 1),
    );
    socket.destroy();
    return null;
  } on SocketException {
    return '로컬 Supabase 스택에 닿지 않는다(supabase start)';
  }
}

Future<SupabaseClient> signUpLocal() async {
  final client = SupabaseClient(
    _env['SUPABASE_URL'] as String,
    _env['SUPABASE_PUBLISHABLE_KEY'] as String,
    // 테스트 클라이언트에는 세션 저장소가 없어 PKCE 대신 implicit 흐름을 쓴다
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
  );
  final id = Random().nextInt(1 << 32).toRadixString(16);
  await client.auth.signUp(
    email: 'test-$id@example.com',
    password: 'password-$id',
  );
  return client;
}
