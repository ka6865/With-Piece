import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';

const names = {
  '32060': '속초시',
  '32400': '고성군',
  '32410': '양양군',
  '37020': '경주시',
  '11140': '마포구',
};

PhotoDay d(int month, int day, String region) =>
    PhotoDay(DateTime(2026, month, day), region);

void main() {
  test('연속된 날을 하나의 후보로 묶고 하루에 여러 조각을 모두 넣는다', () {
    final candidates = tripCandidates(
      [d(10, 3, '32060'), d(10, 4, '32400'), d(10, 4, '32410')],
      home: const {},
      existing: const [],
      regionNames: names,
    );
    expect(candidates, hasLength(1));
    expect(
      candidates.single.range,
      DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 4)),
    );
    expect(candidates.single.regionIds, ['32060', '32400', '32410']);
    expect(candidates.single.title, '속초시 고성군 양양군 1박 2일');
  });

  test('하루 이상 비면 후보가 갈린다', () {
    final candidates = tripCandidates(
      [d(10, 3, '32060'), d(10, 5, '32400')],
      home: const {},
      existing: const [],
      regionNames: names,
    );
    expect(candidates.map((c) => c.title), ['고성군', '속초시']);
  });

  test('생활권 조각은 후보에서 빠진다', () {
    final candidates = tripCandidates(
      [d(10, 1, '11140'), d(10, 3, '11140'), d(10, 3, '37020')],
      home: const {'11140'},
      existing: const [],
      regionNames: names,
    );
    expect(candidates.single.regionIds, ['37020']);
    expect(candidates.single.range.start, DateTime(2026, 10, 3));
  });

  test('확인하거나 버린 여행 기간에 걸친 날은 다시 후보가 되지 않는다', () {
    final candidates = tripCandidates(
      [d(10, 3, '32060'), d(10, 4, '32400'), d(10, 5, '32410')],
      home: const {},
      existing: [DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 4))],
      regionNames: names,
    );
    expect(candidates.single.regionIds, ['32410']);
    expect(candidates.single.title, '양양군');
  });

  test('후보는 최신 여행이 먼저 온다', () {
    final candidates = tripCandidates(
      [d(3, 1, '37020'), d(10, 3, '32060')],
      home: const {},
      existing: const [],
      regionNames: names,
    );
    expect(candidates.map((c) => c.regionIds.single), ['32060', '37020']);
  });
}
