import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_sharing_repository.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/home_regions.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';

import 'support.dart';

Future<void> main() async {
  final skip = await localStackSkipReason();

  test('교집합·확인·중복 확인·버림·생활권 덮어쓰기', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    final coupleA = CoupleRepository(a);
    await CoupleRepository(
      b,
    ).join((await coupleA.createInvite()).valueOrThrow.code);
    await coupleA.setStartedOn(DateTime(2026, 1, 1));
    final coupleId = (await coupleA.current()).valueOrThrow!.id;

    final sokcho = PhotoDay(DateTime(2026, 10, 3), '32060');
    expect((await TripRepository(a).matchedDays()).valueOrThrow, isEmpty);
    await PhotoSharingRepository(
      a,
    ).update(coupleId, approve: {sokcho: 3}, revoke: {});
    await PhotoSharingRepository(
      b,
    ).update(coupleId, approve: {sokcho: 1}, revoke: {});
    final trips = TripRepository(a);
    expect((await trips.matchedDays()).valueOrThrow, [sokcho]);

    final range = DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 3));
    final id = (await trips.confirm(
      title: '속초시',
      range: range,
      regionIds: ['32060'],
      source: TripSource.auto,
    )).valueOrThrow;
    final list = (await TripRepository(b).trips(coupleId)).valueOrThrow;
    expect(list.single.id, id);
    expect(list.single.regionIds, ['32060']);
    expect(list.single.range, range);

    expect(
      await TripRepository(b).confirm(
        title: '속초시',
        range: range,
        regionIds: ['32060'],
        source: TripSource.auto,
      ),
      isA<Err<String>>().having((e) => e.error, 'error', AppError.validation),
    );

    await trips.dismiss(DateRange(DateTime(2026, 3, 1), DateTime(2026, 3, 2)));
    expect(
      (await trips.trips(coupleId)).valueOrThrow.map((t) => t.status),
      containsAll([TripStatus.confirmed, TripStatus.dismissed]),
    );

    await trips.setOverride(coupleId, '11140', OverrideKind.home);
    expect((await TripRepository(b).overrides(coupleId)).valueOrThrow, {
      '11140': OverrideKind.home,
    });
    await trips.setOverride(coupleId, '11140', null);
    expect((await trips.overrides(coupleId)).valueOrThrow, isEmpty);
  }, skip: skip);

  test('새 커플의 여행 목록에 아카이브된 이전 커플의 여행이 섞이지 않는다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    final c = await signUpLocal();
    final coupleA = CoupleRepository(a);
    await CoupleRepository(
      b,
    ).join((await coupleA.createInvite()).valueOrThrow.code);
    final oldId = (await coupleA.current()).valueOrThrow!.id;
    await TripRepository(a).confirm(
      title: '속초시',
      range: DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 3)),
      regionIds: ['32060'],
      source: TripSource.manual,
    );
    await coupleA.archive();
    await CoupleRepository(
      c,
    ).join((await coupleA.createInvite()).valueOrThrow.code);
    final newId = (await coupleA.current()).valueOrThrow!.id;
    expect((await TripRepository(a).trips(oldId)).valueOrThrow, hasLength(1));
    expect((await TripRepository(a).trips(newId)).valueOrThrow, isEmpty);
  }, skip: skip);
}
