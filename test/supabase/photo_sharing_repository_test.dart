import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/data/repositories/fetch_all.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_sharing_repository.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'support.dart';

Future<void> main() async {
  final skip = await localStackSkipReason();
  test('구버전 스캔은 기존 승인을 바꾸지 못하고 명시적 승인과 철회만 반영된다', () async {
    final client = await signUpLocal();
    final partner = await signUpLocal();
    addTearDown(client.dispose);
    addTearDown(partner.dispose);
    final couple = CoupleRepository(client);
    (await CoupleRepository(
      partner,
    ).join((await couple.createInvite()).valueOrThrow.code)).valueOrThrow;
    (await couple.setStartedOn(DateTime(2026, 1, 1))).valueOrThrow;
    final cid = (await couple.current()).valueOrThrow!.id;
    final dayA = PhotoDay(DateTime(2026, 10, 3), '32060');
    final dayB = PhotoDay(DateTime(2026, 10, 4), '32400');
    final shares = PhotoSharingRepository(client);
    (await shares.update(cid, approve: {dayA: 7}, revoke: {})).valueOrThrow;

    await client.rpc(
      'sync_photo_days',
      params: {
        'p_couple_id': cid,
        'p_rows': [
          {'day': '2026-10-03', 'region_id': '32060', 'photo_count': 1},
          {'day': '2026-10-04', 'region_id': '32400', 'photo_count': 2},
        ],
      },
    );
    expect((await shares.approvedWithCounts(cid)).valueOrThrow, {dayA: 7});
    expect(await client.from('photo_days').select('photo_count'), [
      {'photo_count': 7},
    ]);

    (await shares.update(cid, approve: {dayB: 2}, revoke: {})).valueOrThrow;
    (await shares.update(cid, approve: {}, revoke: {dayA})).valueOrThrow;
    expect((await shares.approvedWithCounts(cid)).valueOrThrow, {dayB: 2});
    expect(await client.from('photo_days').select('photo_count'), [
      {'photo_count': 2},
    ]);
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
    final partner = await signUpLocal();
    addTearDown(partner.dispose);
    final couple = CoupleRepository(client);
    (await CoupleRepository(
      partner,
    ).join((await couple.createInvite()).valueOrThrow.code)).valueOrThrow;
    (await couple.setStartedOn(DateTime(2026, 1, 1))).valueOrThrow;
    final coupleId = (await couple.current()).valueOrThrow!.id;
    (await PhotoSharingRepository(client).update(
      coupleId,
      approve: {PhotoDay(DateTime(2026, 10, 3), '32060'): 4},
      revoke: {},
    )).valueOrThrow;
    final offsets = <int>[];
    final all = await fetchAll<Map<String, dynamic>>((from, to) {
      offsets.add(from);
      return client.from('photo_days').select().range(from, to);
    });
    expect(all, hasLength(1));
    expect(offsets, [0, 1]);
  }, skip: skip);

  test('승인·철회와 커플 전환에 따라 교집합을 다시 계산한다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    final ca = CoupleRepository(a);
    await CoupleRepository(b).join((await ca.createInvite()).valueOrThrow.code);
    await ca.setStartedOn(DateTime(2026, 1, 1));
    final cid = (await ca.current()).valueOrThrow!.id;
    final day = PhotoDay(DateTime(2026, 10, 3), '32060');
    final secret = PhotoDay(DateTime(2026, 10, 4), '32400');
    final sa = PhotoSharingRepository(a);
    final sb = PhotoSharingRepository(b);
    expect((await TripRepository(b).matchedDays()).valueOrThrow, isEmpty);
    expect(
      await sa.update(cid, approve: {day: 1}, revoke: {}),
      isA<Ok<void>>(),
    );
    expect((await sa.approvedWithCounts(cid)).valueOrThrow, {day: 1});
    expect((await sb.approvedWithCounts(cid)).valueOrThrow, isEmpty);
    await sb.update(cid, approve: {day: 1, secret: 1}, revoke: {});
    expect((await TripRepository(b).matchedDays()).valueOrThrow, [day]);
    await sa.update(cid, approve: {}, revoke: {day});
    expect((await TripRepository(b).matchedDays()).valueOrThrow, isEmpty);
    await ca.archive();
    final c = await signUpLocal();
    await CoupleRepository(c).join((await ca.createInvite()).valueOrThrow.code);
    final newId = (await ca.current()).valueOrThrow!.id;
    expect(
      await sa.update(cid, approve: {day: 1}, revoke: {}),
      isA<Err<void>>(),
    );
    expect((await sa.approvedWithCounts(newId)).valueOrThrow, isEmpty);
  }, skip: skip);
}
