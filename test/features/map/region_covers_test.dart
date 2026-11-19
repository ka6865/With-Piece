import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/region_cover_repository.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'package:woori_piece/features/map/region_covers.dart';

PhotoRecord photo(String id, String region, int day) => PhotoRecord(
  id: id,
  tripId: 't',
  regionId: region,
  objectKey: 'c1/t/$id.heic',
  uploadedBy: 'me',
  takenAt: DateTime(2026, 10, day),
  width: 4,
  height: 3,
);

void main() {
  final photos = [
    photo('a', '32060', 1),
    photo('b', '32060', 5),
    photo('c', '37020', 2),
  ];

  test('고른 적 없는 조각은 가장 늦게 찍은 사진을 가운데 구도로 쓴다', () {
    final covers = effectiveCovers(const {}, photos);
    expect(covers['32060']!.$1.id, 'b');
    expect(covers['32060']!.$2.scale, 1);
    expect(covers['37020']!.$1.id, 'c');
    expect(covers.containsKey('11010'), isFalse);
  });

  test('고른 사진과 구도를 쓰고, 그 사진이 지워지면 자동 대표로 돌아간다', () {
    const chosen = RegionCover(
      regionId: '32060',
      photoId: 'a',
      scale: 2,
      centerX: 0.3,
      centerY: 0.7,
    );
    expect(effectiveCovers({'32060': chosen}, photos)['32060']!.$2, chosen);
    final gone = effectiveCovers({'32060': chosen}, photos.skip(1));
    expect(gone['32060']!.$1.id, 'b');
  });

  test('같은 여행의 다른 조각 사진을 고르면 그 조각에 사진이 없어도 보인다', () {
    const chosen = RegionCover(regionId: '31370', photoId: 'a');
    final covers = effectiveCovers({'31370': chosen}, photos);
    expect(covers['31370']!.$1.id, 'a');
  });

  test('대표 사진 후보는 그 조각 사진과 그 조각이 든 여행의 사진이다', () {
    Trip trip(String id, List<String> regions) => Trip(
      id: id,
      title: '',
      range: DateRange(DateTime(2026, 10, 1), DateTime(2026, 10, 2)),
      status: TripStatus.confirmed,
      source: TripSource.auto,
      regionIds: regions,
    );
    PhotoRecord inTrip(String id, String tripId, String region, int day) =>
        PhotoRecord(
          id: id,
          tripId: tripId,
          regionId: region,
          objectKey: 'c1/$tripId/$id.heic',
          uploadedBy: 'me',
          takenAt: DateTime(2026, 10, day),
          width: 4,
          height: 3,
        );
    final all = [
      inTrip('chuncheon', 'gp', '32010', 2),
      inTrip('gapyeong', 'gp', '31370', 1),
      inTrip('other', 'x', '32010', 3),
    ];
    final trips = [
      trip('gp', ['32010', '31370']),
      trip('x', ['32010']),
    ];
    expect(coverCandidates(all, trips, '31370').map((p) => p.id), [
      'gapyeong',
      'chuncheon',
    ]);
  });
}
