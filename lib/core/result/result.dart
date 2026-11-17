import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

// Repository의 반환 타입. 예외를 UI까지 던지지 않고 도메인 에러로 바꾼다(설계 12장)
sealed class Result<T> {
  const Result();
}

final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.error);

  final AppError error;
}

enum AppError {
  network,
  authExpired,
  permissionDenied,
  validation,
  quotaExceeded,
  photoPermission,
  unknown,
}

// provider처럼 예외로 실패를 알리는 곳에서 쓴다. AsyncError의 error가 AppError가 된다
extension ResultValue<T> on Result<T> {
  T get valueOrThrow => switch (this) {
    Ok(:final value) => value,
    Err(:final error) => throw error,
  };
}

Future<Result<T>> guard<T>(Future<T> Function() body) async {
  try {
    return Ok(await body());
  } catch (error) {
    return Err(appErrorOf(error));
  }
}

AppError appErrorOf(Object error) => switch (error) {
  SocketException() || TimeoutException() => AppError.network,
  // 42501 RLS·권한 거부, 23xxx 제약 위반, P0001 RPC가 알린 업무 규칙 위반
  PostgrestException(code: '42501') => AppError.permissionDenied,
  PostgrestException(code: 'P0001') => AppError.validation,
  PostgrestException(code: final code?) when code.startsWith('23') =>
    AppError.validation,
  AuthException(statusCode: '401') => AppError.authExpired,
  StorageException(statusCode: '413') => AppError.quotaExceeded,
  StorageException(statusCode: '403') => AppError.permissionDenied,
  _ => AppError.unknown,
};
