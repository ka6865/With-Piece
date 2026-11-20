import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/scan_store.dart';

void main() {
  late Directory dir;
  late ScanStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('scan_store');
    ScanStore.allowUserAfterDeletionCanceled('user-a');
    store = ScanStore(dir, userId: 'user-a');
  });
  tearDown(() {
    ScanStore.allowUserAfterDeletionCanceled('user-a');
    dir.deleteSync(recursive: true);
  });

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
    File('${dir.path}/user-a/photo_days.json.tmp').writeAsStringSync('{"깨진');
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

  test('계정마다 캐시가 분리되고 탈퇴한 계정의 캐시만 지운다', () async {
    final other = ScanStore(dir, userId: 'user-b');
    await store.write(ScanSnapshot({sokcho: 2}, DateTime(2026, 11, 1)));
    await other.write(ScanSnapshot({goseong: 3}, DateTime(2026, 11, 2)));

    await store.clearForDeletion(ScanStore.blockUser(store.userId));

    expect((await store.read()).days, isEmpty);
    expect((await other.read()).days, {goseong: 3});
    expect(store.isDeletionPending, isTrue);
  });

  test('공용 문서 폴더의 이전 스캔 캐시와 임시 파일을 지운다', () async {
    File('${dir.path}/photo_days.json').writeAsStringSync('legacy');
    File('${dir.path}/photo_days.json.tmp').writeAsStringSync('legacy');

    await ScanStore.removeLegacyCache(dir);

    expect(await File('${dir.path}/photo_days.json').exists(), isFalse);
    expect(await File('${dir.path}/photo_days.json.tmp').exists(), isFalse);
  });

  test('이전 계정 경로의 스캔 파일만 삭제한다', () async {
    final account = Directory(
      '${dir.path}/73557da8-1a24-4c7f-a866-2aca16571075',
    )..createSync();
    final scan = File('${account.path}/photo_days.json')..createSync();
    final other = File('${account.path}/settings.json')..createSync();
    final protected = Directory('${dir.path}/scan_snapshots')..createSync();
    final current = File('${protected.path}/photo_days.json')..createSync();

    await ScanStore.removeLegacyAccountCaches(dir);

    expect(scan.existsSync(), isFalse);
    expect(other.existsSync(), isTrue);
    expect(current.existsSync(), isTrue);
  });

  test('이전 캐시를 지우지 못했으면 다음 호출에서 다시 지운다', () async {
    final file = File('${dir.path}/photo_days.json')..createSync();
    // 쓰기 권한을 빼 삭제를 실패시킨다
    Process.runSync('chmod', ['555', dir.path]);
    await expectLater(
      ScanStore.removeLegacyCache(dir),
      throwsA(isA<FileSystemException>()),
    );
    Process.runSync('chmod', ['755', dir.path]);

    await ScanStore.removeLegacyCache(dir);

    expect(file.existsSync(), isFalse);
  });
}
