import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/region_cover_repository.dart';
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
}
