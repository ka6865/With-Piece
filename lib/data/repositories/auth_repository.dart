import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';

class AuthRepository {
  const AuthRepository(this._client, this._prefs);

  // Apple은 4단계에서 이 목록에 더한다. 화면은 목록만 보고 버튼을 만든다(설계 10장)
  static const providers = [OAuthProvider.kakao];
  static const callbackUrl = 'kr.wooripiece.wooripiece://login-callback';
  static const _lastProviderKey = 'last_provider';
  // 앱 안 브라우저(SFSafariViewController)는 콜백 딥링크로 이동해도 스스로 닫히지 않는다.
  // 외부 브라우저로 열어야 콜백이 앱을 바로 다시 띄운다
  static const _launchMode = LaunchMode.externalApplication;

  final SupabaseClient _client;
  final SharedPreferences _prefs;

  // 계정 갈라짐을 줄이려고 로그인 화면에서 먼저 보여준다(설계 10.2)
  OAuthProvider? get lastProvider {
    final name = _prefs.getString(_lastProviderKey);
    return OAuthProvider.values.where((p) => p.name == name).firstOrNull;
  }

  Future<void> rememberProvider(OAuthProvider provider) =>
      _prefs.setString(_lastProviderKey, provider.name);

  Future<Result<void>> signIn(OAuthProvider provider) => guard(() async {
    await rememberProvider(provider);
    await _client.auth.signInWithOAuth(
      provider,
      redirectTo: callbackUrl,
      authScreenLaunchMode: _launchMode,
    );
  });

  // 로그인된 세션에 신원을 더한다. signInWithOAuth를 쓰면 새 계정으로 갈라진다(설계 10.2)
  Future<Result<void>> link(OAuthProvider provider) => guard(
    () => _client.auth.linkIdentity(
      provider,
      redirectTo: callbackUrl,
      authScreenLaunchMode: _launchMode,
    ),
  );

  Future<Result<List<UserIdentity>>> identities() =>
      guard(() => _client.auth.getUserIdentities());

  // 마지막 신원을 끊으면 로그인 수단이 사라진다
  Future<Result<void>> unlink(UserIdentity identity) async {
    final current = await identities();
    return switch (current) {
      Ok(:final value) when value.length < 2 => const Err(AppError.validation),
      Ok() => guard(() => _client.auth.unlinkIdentity(identity)),
      Err(:final error) => Err(error),
    };
  }

  Future<Result<void>> signOut() => guard(() => _client.auth.signOut());
}
