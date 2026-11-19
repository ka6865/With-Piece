import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'photo_days.dart';

class ScanSnapshot {
  const ScanSnapshot(this.days, this.scannedAt);

  static const empty = ScanSnapshot({}, null);

  // 사귄 날과 무관한 전체 결과. 기기 밖으로 나가지 않는다(설계 5.1)
  final Map<PhotoDay, int> days;
  final DateTime? scannedAt;

  ScanSnapshot merge(Map<PhotoDay, int> increment, DateTime scannedAt) {
    final merged = {...days};
    increment.forEach((day, count) => merged[day] = (merged[day] ?? 0) + count);
    return ScanSnapshot(merged, scannedAt);
  }

  @override
  bool operator ==(Object other) =>
      other is ScanSnapshot &&
      other.scannedAt == scannedAt &&
      mapEquals(other.days, days);

  @override
  int get hashCode => Object.hash(scannedAt, days.length);
}

// 스캔 결과와 마지막 스캔 시각을 파일 하나에 두어 한 번에 바꾼다.
// 따로 두면 둘 중 하나만 저장된 채 앱이 꺼질 수 있다
class ScanStore {
  ScanStore(this.directory, {required this.userId});

  final Directory directory;
  final String userId;

  static final _blockedUsers = <String, Object>{};
  static final _locks = <String, Future<void>>{};
  static final _legacyCleanup = <String, Future<void>>{};

  static void blockUser(String userId) => _blockedUsers[userId] = Object();

  static Object? deletionBlockFor(String userId) => _blockedUsers[userId];

  static void applyDeletionStatus(
    String userId, {
    required Object? blockAtRequest,
    required bool pending,
  }) {
    // 조회하는 사이 이 기기에서 새 삭제를 요청했다면 최신 차단을 유지한다.
    if (!identical(blockAtRequest, _blockedUsers[userId])) return;
    if (pending) {
      _blockedUsers.putIfAbsent(userId, Object.new);
    } else {
      _blockedUsers.remove(userId);
    }
  }

  static void allowUserAfterDeletionCanceled(String userId) =>
      _blockedUsers.remove(userId);

  static Future<void> removeLegacySharedCache(Directory documents) {
    final path = documents.absolute.path;
    return _legacyCleanup.putIfAbsent(path, () async {
      for (final name in ['photo_days.json', 'photo_days.json.tmp']) {
        final file = File('$path/$name');
        if (await file.exists()) await file.delete();
      }
    });
  }

  Directory get _userDirectory =>
      Directory('${directory.path}/${Uri.encodeComponent(userId)}');

  File get _file => File('${_userDirectory.path}/photo_days.json');

  bool get isDeletionPending => _blockedUsers.containsKey(userId);

  void blockForDeletion() => blockUser(userId);

  void allowAfterDeletionCanceled() => allowUserAfterDeletionCanceled(userId);

  Future<T> runExclusive<T>(Future<T> Function() action) {
    final key = _userDirectory.absolute.path;
    final previous = _locks[key] ?? Future<void>.value();
    final release = Completer<void>();
    final next = previous.then((_) => release.future);
    _locks[key] = next;
    return previous.then((_) => action()).whenComplete(() {
      release.complete();
      if (identical(_locks[key], next)) _locks.remove(key);
    });
  }

  Future<void> clearForDeletion() {
    blockForDeletion();
    return runExclusive(() async {
      if (await _userDirectory.exists()) {
        await _userDirectory.delete(recursive: true);
      }
    });
  }

  Future<ScanSnapshot> read() async {
    if (!await _file.exists()) return ScanSnapshot.empty;
    final json = jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
    return ScanSnapshot({
      for (final row in json['days'] as List)
        PhotoDay(DateTime.parse(row[0] as String), row[1] as String):
            row[2] as int,
    }, DateTime.parse(json['scannedAt'] as String));
  }

  // 임시 파일에 쓴 뒤 rename으로 바꿔 쓰기 도중 종료돼도 이전 내용이 남는다
  Future<void> write(ScanSnapshot snapshot) async {
    await _userDirectory.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({
        'scannedAt': snapshot.scannedAt!.toIso8601String(),
        'days': [
          for (final MapEntry(key: day, value: count) in snapshot.days.entries)
            [day.day.toIso8601String().substring(0, 10), day.regionId, count],
        ],
      }),
      flush: true,
    );
    await tmp.rename(_file.path);
  }
}
