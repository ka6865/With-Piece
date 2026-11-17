import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/photo_day_repository.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/scan_store.dart';
import 'package:woori_piece/features/scan/scan_sync.dart';

class CountingRepo extends PhotoDayRepository {
  CountingRepo() : super(SupabaseClient('http://127.0.0.1:1', 'unused'));

  final calls = <Map<PhotoDay, int>>[];

  @override
  Future<Result<void>> replaceAll(Map<PhotoDay, int> days) async {
    calls.add(days);
    return const Ok(null);
  }
}

void main() {
  test('같은 스캔 결과와 같은 사귄 날이면 다시 올리지 않는다', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = CountingRepo();
    final sync = ScanSync(repo, await SharedPreferences.getInstance());
    final snapshot = ScanSnapshot({
      PhotoDay(DateTime(2026, 10, 3), '32060'): 1,
    }, DateTime(2026, 11, 1));
    await sync.sync(snapshot, DateTime(2026, 1, 1));
    await sync.sync(snapshot, DateTime(2026, 1, 1));
    expect(repo.calls, hasLength(1));
    await sync.sync(snapshot, DateTime(2025, 1, 1));
    expect(repo.calls, hasLength(2));
  });
}
