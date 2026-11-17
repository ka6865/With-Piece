import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';

import 'support.dart';

T valueOf<T>(Result<T> result) => switch (result) {
  Ok(:final value) => value,
  Err(:final error) => throw StateError('$error'),
};

Future<void> main() async {
  final skip = await localStackSkipReason();
  test('초대를 만들고 상대가 합류하면 같은 커플이 된다', () async {
    final a = CoupleRepository(await signUpLocal());
    final b = CoupleRepository(await signUpLocal());
    expect(valueOf(await a.current()), isNull);

    final invite = valueOf(await a.createInvite());
    expect(invite.code.length, 10);
    expect(valueOf(await a.myInvite())?.code, invite.code);
    expect(valueOf(await b.join(invite.code)), JoinOutcome.joined);

    final coupleA = valueOf(await a.current())!;
    final coupleB = valueOf(await b.current())!;
    expect(coupleA.id, coupleB.id);
    expect(coupleA.startedOn, isNull);
  }, skip: skip);

  test('합류 실패를 결과값으로 구분한다', () async {
    final a = CoupleRepository(await signUpLocal());
    final invite = valueOf(await a.createInvite());
    expect(valueOf(await a.join(invite.code)), JoinOutcome.self);
    final b = CoupleRepository(await signUpLocal());
    expect(valueOf(await b.join('zzzzzzzzzz')), JoinOutcome.invalidCode);
  }, skip: skip);

  test('커플이 있으면 초대 발급이 검증 오류다', () async {
    final a = CoupleRepository(await signUpLocal());
    final b = CoupleRepository(await signUpLocal());
    await b.join(valueOf(await a.createInvite()).code);
    expect(
      await a.createInvite(),
      isA<Err<Invite>>().having((e) => e.error, 'error', AppError.validation),
    );
  }, skip: skip);

  test('사귄 날을 정하고 아카이브하면 활성 커플이 사라진다', () async {
    final a = CoupleRepository(await signUpLocal());
    final b = CoupleRepository(await signUpLocal());
    await b.join(valueOf(await a.createInvite()).code);
    expect(await a.setStartedOn(DateTime(2026, 1, 1)), isA<Ok<void>>());
    expect(valueOf(await b.current())!.startedOn, DateTime(2026, 1, 1));
    expect(await a.archive(), isA<Ok<void>>());
    expect(valueOf(await b.current()), isNull);
  }, skip: skip);
}
