import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/data/repositories/fetch_all.dart';

void main() {
  test('서버 상한이 요청보다 낮아도 실제 반환 수만큼 이동해 빈 페이지까지 읽는다', () async {
    final offsets = <int>[];
    final rows = await fetchAll<int>((from, to) async {
      offsets.add(from);
      return List.generate(7, (i) => i).skip(from).take(3).toList();
    });
    expect(rows, [0, 1, 2, 3, 4, 5, 6]);
    expect(offsets, [0, 3, 6, 7]);
  });
  test('끝을 넘긴 명시적 offset의 PGRST103만 종료로 처리한다', () async {
    final rows = await fetchAll<int>((from, to) async {
      if (from == 0) return [1, 2];
      throw const PostgrestException(
        message: 'Requested range not satisfiable',
        code: 'PGRST103',
        details: 'An offset of 2 was requested, but there are only 2 rows.',
      );
    });
    expect(rows, [1, 2]);
  });
  test('다른 범위 오류와 권한 오류를 숨기지 않는다', () async {
    for (final error in [
      const PostgrestException(message: 'invalid range', code: 'PGRST103'),
      const PostgrestException(message: 'denied', code: '42501'),
      const PostgrestException(
        message: 'range',
        code: 'PGRST103',
        details: 'An offset of 0 was requested, but there are only 2 rows.',
      ),
    ]) {
      await expectLater(
        fetchAll<int>((from, to) async => throw error),
        throwsA(same(error)),
      );
    }
  });
}
