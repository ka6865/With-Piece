import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_day_repository.dart';
import 'package:woori_piece/data/repositories/photo_sharing_repository.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'support.dart';

Future<void> main() async {
  final skip = await localStackSkipReason();
  test('기존 원본이 있어도 승인 전 미공개, 승인·철회와 커플 전환을 반영한다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    final ca = CoupleRepository(a);
    await CoupleRepository(b).join((await ca.createInvite()).valueOrThrow.code);
    await ca.setStartedOn(DateTime(2026, 1, 1));
    final cid = (await ca.current()).valueOrThrow!.id;
    final day = PhotoDay(DateTime(2026, 10, 3), '32060');
    final secret = PhotoDay(DateTime(2026, 10, 4), '32400');
    await PhotoDayRepository(a).replaceAll({day: 1, secret: 1});
    await PhotoDayRepository(b).replaceAll({day: 1, secret: 1});
    final sa = PhotoSharingRepository(a);
    final sb = PhotoSharingRepository(b);
    expect((await TripRepository(b).matchedDays()).valueOrThrow, isEmpty);
    expect(await sa.replace(cid, {day}), isA<Ok<void>>());
    expect((await sa.approved(cid)).valueOrThrow, {day});
    expect((await sb.approved(cid)).valueOrThrow, isEmpty);
    await sb.replace(cid, {day, secret});
    expect((await TripRepository(b).matchedDays()).valueOrThrow, [day]);
    await sa.replace(cid, {});
    expect((await TripRepository(b).matchedDays()).valueOrThrow, isEmpty);
    await ca.archive();
    final c = await signUpLocal();
    await CoupleRepository(c).join((await ca.createInvite()).valueOrThrow.code);
    final newId = (await ca.current()).valueOrThrow!.id;
    expect(await sa.replace(cid, {day}), isA<Err<void>>());
    expect((await sa.approved(newId)).valueOrThrow, isEmpty);
  }, skip: skip);
}
