import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/photo_day_repository.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/scan_store.dart';
import 'package:woori_piece/features/scan/scan_sync.dart';

import 'support.dart';

Future<void> main() async {
  final skip = await localStackSkipReason();

  final before = PhotoDay(DateTime(2025, 12, 31), '11010');
  final sokcho = PhotoDay(DateTime(2026, 10, 3), '32060');
  final goseong = PhotoDay(DateTime(2026, 10, 4), '32400');

  test('사귄 날 이후만 올리고, 기준이 바뀌면 다시 맞춘다', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = PhotoDayRepository(await signUpLocal());
    final sync = ScanSync(repo, await SharedPreferences.getInstance());
    final snapshot = ScanSnapshot({
      before: 1,
      sokcho: 2,
      goseong: 1,
    }, DateTime(2026, 11, 1));

    await sync.sync(snapshot, DateTime(2026, 1, 1));
    expect((await repo.mine()).valueOrThrow, {sokcho: 2, goseong: 1});

    // 사귄 날을 앞당기면 그 사이 날짜가 올라간다
    await sync.sync(snapshot, DateTime(2025, 1, 1));
    expect((await repo.mine()).valueOrThrow, {
      before: 1,
      sokcho: 2,
      goseong: 1,
    });

    // 늦추면 기준 이전 행이 지워진다
    await sync.sync(snapshot, DateTime(2026, 10, 4));
    expect((await repo.mine()).valueOrThrow, {goseong: 1});
  }, skip: skip);

  test('다시 스캔 결과로 맞추면 사진첩에서 지운 날이 사라진다', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = PhotoDayRepository(await signUpLocal());
    final sync = ScanSync(repo, await SharedPreferences.getInstance());
    await sync.sync(
      ScanSnapshot({sokcho: 2, goseong: 1}, DateTime(2026, 11, 1)),
      DateTime(2026, 1, 1),
    );
    await sync.sync(
      ScanSnapshot({goseong: 3}, DateTime(2026, 11, 2)),
      DateTime(2026, 1, 1),
    );
    expect((await repo.mine()).valueOrThrow, {goseong: 3});
  }, skip: skip);
}
