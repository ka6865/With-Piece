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
  Future<Result<void>> sync(String coupleId, Map<PhotoDay, int> days) async {
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
    await sync.sync(
      snapshot,
      DateTime(2026, 1, 1),
      userId: 'a',
      coupleId: 'c1',
    );
    await sync.sync(
      snapshot,
      DateTime(2026, 1, 1),
      userId: 'a',
      coupleId: 'c1',
    );
    expect(repo.calls, hasLength(1));
    await sync.sync(
      snapshot,
      DateTime(2025, 1, 1),
      userId: 'a',
      coupleId: 'c1',
    );
    expect(repo.calls, hasLength(2));
  });
  test('결과가 같아도 새 스캔이면 다른 기기가 덮어쓴 서버 목록을 다시 맞춘다', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = CountingRepo();
    final sync = ScanSync(repo, await SharedPreferences.getInstance());
    final day = PhotoDay(DateTime(2026, 10, 3), '32060');
    await sync.sync(
      ScanSnapshot({day: 2}, DateTime(2026, 11, 1)),
      DateTime(2026, 1, 1),
      userId: 'a',
      coupleId: 'c1',
    );
    await sync.sync(
      ScanSnapshot({day: 2}, DateTime(2026, 11, 2)),
      DateTime(2026, 1, 1),
      userId: 'a',
      coupleId: 'c1',
    );
    expect(repo.calls, hasLength(2));
  });
  test('계정과 커플이 바뀌거나 삭제 후 무효화하면 같은 스캔도 다시 올린다', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = CountingRepo();
    final sync = ScanSync(repo, await SharedPreferences.getInstance());
    final snapshot = ScanSnapshot({
      PhotoDay(DateTime(2026, 10, 3), '32060'): 1,
    }, DateTime(2026, 11, 1));
    final started = DateTime(2026, 1, 1);
    await sync.sync(snapshot, started, userId: 'a', coupleId: 'c1');
    await sync.sync(snapshot, started, userId: 'b', coupleId: 'c1');
    await sync.sync(snapshot, started, userId: 'b', coupleId: 'c2');
    expect(repo.calls, hasLength(3));
    await sync.clearForUser('b');
    await sync.sync(snapshot, started, userId: 'b', coupleId: 'c2');
    expect(repo.calls, hasLength(4));
  });
}
