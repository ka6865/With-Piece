import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/result/result.dart';
import '../../data/repositories/photo_day_repository.dart';
import 'scan_store.dart';

// 사귄 날 이후의 스캔 결과만 서버 목록으로 맞춘다. 사귀기 전 기록은 기기를
// 떠나지 않는다(설계 5.2)
class ScanSync {
  ScanSync(this._repository, this._prefs);

  static const _syncedKey = 'synced_scan';

  final PhotoDayRepository _repository;
  final SharedPreferences _prefs;

  // 같은 스캔 결과를 같은 사귄 날 기준으로 이미 올렸으면 건너뛴다.
  // 상대가 사귄 날을 바꾸거나 새 스캔이 쌓이면 키가 달라져 다시 맞춘다
  Future<Result<void>> sync(
    ScanSnapshot snapshot,
    DateTime startedOn, {
    required String userId,
    required String coupleId,
  }) async {
    final days = {
      for (final MapEntry(key: day, value: count) in snapshot.days.entries)
        if (!day.day.isBefore(startedOn)) day: count,
    };
    final key = sha256
        .convert(
          utf8.encode(
            jsonEncode([
              coupleId,
              startedOn.toIso8601String(),
              for (final entry
                  in days.entries.toList()..sort((a, b) {
                    final date = a.key.day.compareTo(b.key.day);
                    return date == 0
                        ? a.key.regionId.compareTo(b.key.regionId)
                        : date;
                  }))
                [
                  entry.key.day.toIso8601String().substring(0, 10),
                  entry.key.regionId,
                  entry.value,
                ],
            ]),
          ),
        )
        .toString();
    final storageKey = '$_syncedKey:$userId';
    if (_prefs.getString(storageKey) == key) return const Ok(null);
    final result = await _repository.sync(coupleId, days);
    if (result is Ok) await _prefs.setString(storageKey, key);
    return result;
  }

  Future<void> clearForUser(String userId) async {
    await _prefs.remove('$_syncedKey:$userId');
  }
}
