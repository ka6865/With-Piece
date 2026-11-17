import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/progress.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';

Trip trip(String id, TripStatus status, List<String> regions) => Trip(
  id: id,
  title: '',
  range: DateRange(DateTime(2026, 1, 1), DateTime(2026, 1, 1)),
  status: status,
  source: TripSource.auto,
  regionIds: regions,
);

void main() {
  test('칠해진 조각은 확인된 여행 조각과 생활권의 합집합이다', () {
    final filled = filledRegionIds(
      [
        trip('a', TripStatus.confirmed, ['32060', '32400']),
        trip('b', TripStatus.dismissed, ['37020']),
      ],
      {'11140', '32060'},
    );
    expect(filled, {'32060', '32400', '11140'});
  });

  test('시도별 진행률은 같은 조각을 한 번만 센다', () {
    expect(
      filledCountByProvince(
        {'32060', '32400', '11140'},
        {'32060': '32', '32400': '32', '11140': '11'},
      ),
      {'32': 2, '11': 1},
    );
  });
}
