import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/features/album/album_page.dart';

PhotoRecord photo(String id, String tripId) => PhotoRecord(
  id: id,
  tripId: tripId,
  regionId: null,
  objectKey: 'c1/$tripId/$id.jpg',
  uploadedBy: 'user',
  takenAt: null,
  width: 1,
  height: 1,
);

void main() {
  test('앨범 사진 인덱스는 여행 ID별 원본 순서를 보존한다', () {
    final indexed = indexPhotosByTrip([
      photo('p1', 'trip-a'),
      photo('p2', 'trip-b'),
      photo('p3', 'trip-a'),
    ]);

    expect(indexed.keys.toSet(), {'trip-a', 'trip-b'});
    expect(indexed['trip-a']!.map((photo) => photo.id), ['p1', 'p3']);
    expect(indexed['trip-b']!.map((photo) => photo.id), ['p2']);
  });
}
