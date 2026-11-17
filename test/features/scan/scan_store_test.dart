import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/scan_store.dart';

void main() {
  late Directory dir;
  late ScanStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('scan_store');
    store = ScanStore(dir);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  final sokcho = PhotoDay(DateTime(2026, 10, 3), '32060');
  final goseong = PhotoDay(DateTime(2026, 10, 4), '32400');

  test('저장한 결과와 마지막 스캔 시각을 다시 읽는다', () async {
    final empty = await store.read();
    expect(empty.days, isEmpty);
    expect(empty.scannedAt, isNull);
    await store.write(
      ScanSnapshot({sokcho: 2, goseong: 1}, DateTime(2026, 11, 1, 9)),
    );
    final snapshot = await store.read();
    expect(snapshot.days, {sokcho: 2, goseong: 1});
    expect(snapshot.scannedAt, DateTime(2026, 11, 1, 9));
  });

  test('쓰다 남은 임시 파일이 있어도 이전 내용을 읽는다', () async {
    await store.write(ScanSnapshot({sokcho: 2}, DateTime(2026, 11, 1)));
    File('${dir.path}/photo_days.json.tmp').writeAsStringSync('{"깨진');
    expect((await store.read()).days, {sokcho: 2});
  });

  test('증분 결과를 더하면 같은 날·조각의 장수가 합쳐진다', () {
    final merged = ScanSnapshot(
      {sokcho: 2},
      DateTime(2026, 11, 1),
    ).merge({sokcho: 3, goseong: 1}, DateTime(2026, 11, 2));
    expect(merged.days, {sokcho: 5, goseong: 1});
    expect(merged.scannedAt, DateTime(2026, 11, 2));
  });

  test('다시 스캔은 기존 결과를 통째로 바꾼다', () async {
    await store.write(
      ScanSnapshot({sokcho: 2, goseong: 1}, DateTime(2026, 11, 1)),
    );
    await store.write(ScanSnapshot({goseong: 4}, DateTime(2026, 11, 3)));
    expect((await store.read()).days, {goseong: 4});
  });
}
