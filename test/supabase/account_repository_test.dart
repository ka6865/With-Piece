import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/account_repository.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';

import 'support.dart';

Future<void> main() async {
  final skip = await localStackSkipReason();

  test('삭제 요청은 상대에게 삭제 예정일로 보이고 취소하면 사라진다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    await CoupleRepository(
      b,
    ).join((await CoupleRepository(a).createInvite()).valueOrThrow.code);

    expect((await AccountRepository(a).myDeletionDate()).valueOrThrow, isNull);
    await AccountRepository(a).requestDeletion();
    final mine = (await AccountRepository(a).myDeletionDate()).valueOrThrow!;
    expect(mine.difference(DateTime.now()).inDays, inInclusiveRange(29, 30));
    expect((await CoupleRepository(b).current()).valueOrThrow, isNull);
    expect((await AccountRepository(b).partnerDeletionDates()).valueOrThrow, [
      mine,
    ]);

    await AccountRepository(a).cancelDeletion();
    expect((await AccountRepository(a).myDeletionDate()).valueOrThrow, isNull);
    expect(
      (await AccountRepository(b).partnerDeletionDates()).valueOrThrow,
      isEmpty,
    );
  }, skip: skip);

  test('상대가 삭제를 요청하면 지난 기록에 그 커플과 삭제 예정일이 보인다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    await CoupleRepository(
      b,
    ).join((await CoupleRepository(a).createInvite()).valueOrThrow.code);
    final coupleId = (await CoupleRepository(a).current()).valueOrThrow!.id;
    expect((await CoupleRepository(a).archived()).valueOrThrow, isEmpty);

    await AccountRepository(b).requestDeletion();
    final archived = (await CoupleRepository(a).archived()).valueOrThrow;
    expect(archived.single.id, coupleId);
    expect(
      archived.single.partnerDeletionDate,
      (await AccountRepository(b).myDeletionDate()).valueOrThrow,
    );
  }, skip: skip);

  test('재결합 뒤 다시 삭제하면 지난 기록은 각각 보이고 배너는 한 번 표시한다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final left = CoupleRepository(a);
    final right = CoupleRepository(b);
    Future<void> connect() async {
      final invite = (await left.createInvite()).valueOrThrow;
      expect((await right.join(invite.code)).valueOrThrow, JoinOutcome.joined);
    }

    await connect();
    final previous = (await left.current()).valueOrThrow!.id;
    (await left.archive()).valueOrThrow;
    await connect();
    final current = (await left.current()).valueOrThrow!.id;
    expect(current, isNot(previous));

    (await AccountRepository(a).requestDeletion()).valueOrThrow;
    final archives = (await right.archived()).valueOrThrow;
    expect(
      archives.map((archive) => archive.id),
      unorderedEquals([previous, current]),
    );
    expect(
      (await AccountRepository(b).partnerDeletionDates()).valueOrThrow,
      hasLength(1),
    );
  }, skip: skip);
}
