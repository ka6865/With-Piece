import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/auth_repository.dart';

import 'support.dart';

Future<void> main() async {
  final skip = await localStackSkipReason();
  SharedPreferences.setMockInitialValues({});
  test('신원이 하나뿐이면 연결 해제를 거부한다', () async {
    final repository = AuthRepository(
      await signUpLocal(),
      await SharedPreferences.getInstance(),
    );
    final identities = switch (await repository.identities()) {
      Ok(:final value) => value,
      Err(:final error) => throw StateError('$error'),
    };
    expect(identities, hasLength(1));
    expect(
      await repository.unlink(identities.single),
      isA<Err<void>>().having((e) => e.error, 'error', AppError.validation),
    );
  }, skip: skip);
}
