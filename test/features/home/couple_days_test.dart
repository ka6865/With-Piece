import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/home/couple_days.dart';

void main() {
  test('사귄 날을 1일로 센다', () {
    final start = DateTime(2025, 6, 24);
    expect(daysTogether(start, DateTime(2025, 6, 24, 23, 59)), 1);
    expect(daysTogether(start, DateTime(2025, 6, 25)), 2);
    expect(daysTogether(start, DateTime(2026, 6, 24)), 366);
  });

  test('서머타임 없는 날짜 차이로 센다', () {
    expect(daysTogether(DateTime(2024, 3, 9), DateTime(2024, 3, 11, 1)), 3);
  });

  test('사귄 날 표기와 이니셜', () {
    expect(formatStartedOn(DateTime(2025, 6, 4)), '2025.06.04');
    expect(initialOf('민지', '나'), '민');
    expect(initialOf('  ', '나'), '나');
    expect(initialOf(null, '너'), '너');
    expect(initialOf('👩‍❤️‍👨 커플', '나'), '👩‍❤️‍👨');
  });
}
