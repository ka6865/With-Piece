import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/result/result.dart';

void main() {
  test('예외를 설계 12장의 도메인 에러로 바꾼다', () {
    expect(appErrorOf(const SocketException('x')), AppError.network);
    expect(
      appErrorOf(const PostgrestException(message: 'x', code: '42501')),
      AppError.permissionDenied,
    );
    expect(
      appErrorOf(const PostgrestException(message: 'x', code: '23505')),
      AppError.validation,
    );
    expect(
      appErrorOf(const PostgrestException(message: 'x', code: '23514')),
      AppError.validation,
    );
    expect(
      appErrorOf(AuthException('x', statusCode: '401')),
      AppError.authExpired,
    );
    expect(
      appErrorOf(StorageException('x', statusCode: '413')),
      AppError.quotaExceeded,
    );
    // RPC가 raise exception으로 알리는 업무 규칙 위반(already_coupled 등)
    expect(
      appErrorOf(
        const PostgrestException(message: 'already_coupled', code: 'P0001'),
      ),
      AppError.validation,
    );
    expect(appErrorOf(StateError('x')), AppError.unknown);
  });

  test('guard는 성공을 Ok로, 예외를 Err로 감싼다', () async {
    expect(
      await guard(() async => 3),
      isA<Ok<int>>().having((r) => r.value, 'value', 3),
    );
    expect(
      await guard<int>(() async => throw const SocketException('x')),
      isA<Err<int>>().having((r) => r.error, 'error', AppError.network),
    );
  });
}
