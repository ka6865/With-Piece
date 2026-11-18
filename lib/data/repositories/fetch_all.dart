import 'package:supabase_flutter/supabase_flutter.dart';

// 서버가 요청보다 작은 상한을 써도 실제 받은 행 수만큼 다음 범위를 읽는다.
Future<List<T>> fetchAll<T>(Future<List<T>> Function(int, int) page) async {
  final rows = <T>[];
  while (true) {
    final List<T> next;
    try {
      next = await page(rows.length, rows.length + 999);
    } on PostgrestException catch (error) {
      final match = RegExp(
        r'^An offset of (\d+) was requested, but there are only (\d+) rows\.$',
      ).firstMatch(error.details?.toString() ?? '');
      if (error.code == 'PGRST103' &&
          match != null &&
          int.parse(match[1]!) == rows.length &&
          rows.length >= int.parse(match[2]!)) {
        return rows;
      }
      rethrow;
    }
    if (next.isEmpty) return rows;
    rows.addAll(next);
  }
}
