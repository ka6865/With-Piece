import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/data/repositories/fetch_all.dart';
import 'package:woori_piece/features/scan/scan_sync.dart';
import 'package:woori_piece/features/scan/scan_store.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_day_repository.dart';
import 'package:woori_piece/data/repositories/photo_sharing_repository.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'support.dart';

Future<void> main() async {
  final skip = await localStackSkipReason();
  test('두 기기 스캔과 과거 화면의 명시적 변경은 앞선 승인과 최신 미수정 승인을 보존한다', () async {
    final client = await signUpLocal();
    final partner = await signUpLocal();
    addTearDown(client.dispose);
    addTearDown(partner.dispose);
    final couple = CoupleRepository(client);
    await CoupleRepository(
      partner,
    ).join((await couple.createInvite()).valueOrThrow.code);
    await couple.setStartedOn(DateTime(2026, 1, 1));
    final cid = (await couple.current()).valueOrThrow!.id;
    final dayA = PhotoDay(DateTime(2026, 10, 3), '32060');
    final dayB = PhotoDay(DateTime(2026, 10, 4), '32400');
    final repo = PhotoDayRepository(client);
    final shares = PhotoSharingRepository(client);
    SharedPreferences.setMockInitialValues({});
    final deviceA = ScanSync(repo, await SharedPreferences.getInstance());
    SharedPreferences.setMockInitialValues({});
    final deviceB = ScanSync(repo, await SharedPreferences.getInstance());
    Future<Result<void>> scan(
      ScanSync sync,
      Map<PhotoDay, int> days,
      int device,
    ) => sync.sync(
      ScanSnapshot(days, DateTime(2026, 11, device)),
      DateTime(2026, 1, 1),
      userId: client.auth.currentUser!.id,
      coupleId: cid,
    );
    expect(await scan(deviceA, {dayA: 7}, 1), isA<Ok<void>>());
    expect(
      await shares.update(cid, approve: {dayA}, revoke: {}),
      isA<Ok<void>>(),
    );
    expect(await scan(deviceB, {dayB: 2}, 2), isA<Ok<void>>());
    expect((await shares.approvedWithCounts(cid)).valueOrThrow, {dayA: 7});
    expect((await repo.mine()).valueOrThrow, {dayA: 7, dayB: 2});
    // 기기 A의 화면을 연 뒤 기기 B가 새 기록을 승인한다.
    expect(
      await shares.update(cid, approve: {dayB}, revoke: {}),
      isA<Ok<void>>(),
    );
    expect(
      await shares.update(cid, approve: {}, revoke: {dayA}),
      isA<Ok<void>>(),
    );
    expect((await shares.approved(cid)).valueOrThrow, {dayB});
    expect(await scan(deviceA, {}, 3), isA<Ok<void>>());
    expect((await repo.mine()).valueOrThrow, {dayB: 2});
  }, skip: skip);

  test('로컬 HTTP에서 빈 목록과 마지막 범위 이후 PGRST103를 처리한다', () async {
    final client = await signUpLocal();
    addTearDown(client.dispose);
    final rows = await fetchAll<Map<String, dynamic>>(
      (from, to) => client.from('photo_days').select().range(from, to),
    );
    expect(rows, isEmpty);
    await expectLater(
      client
          .from('photo_days')
          .select()
          .range(1, 1000)
          .count(CountOption.exact),
      throwsA(
        isA<PostgrestException>()
            .having((e) => e.code, 'code', 'PGRST103')
            .having(
              (e) => e.details,
              'details',
              'An offset of 1 was requested, but there are only 0 rows.',
            ),
      ),
    );
    final day = PhotoDay(DateTime(2026, 10, 3), '32060');
    expect(
      await PhotoDayRepository(client).replaceAll({day: 4}),
      isA<Ok<void>>(),
    );
    final offsets = <int>[];
    final all = await fetchAll<Map<String, dynamic>>((from, to) {
      offsets.add(from);
      return client.from('photo_days').select().range(from, to);
    });
    expect(all, hasLength(1));
    expect(offsets, [0, 1]);
  }, skip: skip);

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
