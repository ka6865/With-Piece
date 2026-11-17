import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/data/repositories/auth_repository.dart';

void main() {
  test('마지막으로 쓴 제공자를 기억한다', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // 네트워크를 쓰지 않는 경로만 본다
    final client = SupabaseClient('http://127.0.0.1:1', 'unused');
    expect(AuthRepository(client, prefs).lastProvider, isNull);
    await AuthRepository(client, prefs).rememberProvider(OAuthProvider.kakao);
    expect(AuthRepository(client, prefs).lastProvider, OAuthProvider.kakao);
  });
}
