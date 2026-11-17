import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/trip/photo_selection.dart';

LocalPhoto photo(String id, int hour, String region) => LocalPhoto(
  assetId: id,
  takenAt: DateTime(2026, 10, 3, hour),
  regionId: region,
);

void main() {
  test('조각마다 촬영 시각이 고르게 퍼진 N장을 고른다', () {
    final photos = [for (var h = 0; h < 10; h++) photo('s$h', h, '32060')];
    expect(defaultSelection(photos, perRegion: 3), {'s0', 's5', 's9'});
  });

  test('N보다 적으면 전부, 조각마다 따로 센다', () {
    final photos = [
      photo('a', 9, '32060'),
      photo('b', 10, '32060'),
      for (var h = 0; h < 8; h++) photo('g$h', h, '32400'),
    ];
    final selected = defaultSelection(photos, perRegion: 6);
    expect(selected.where((id) => id.startsWith('g')), hasLength(6));
    expect(selected, containsAll(['a', 'b']));
  });

  test('입력 순서와 무관하게 시각 순으로 퍼뜨린다', () {
    final photos = [
      photo('late', 20, '32060'),
      photo('early', 1, '32060'),
      photo('mid', 10, '32060'),
    ];
    expect(defaultSelection(photos, perRegion: 2), {'early', 'late'});
  });

  test('위치가 없는 사진은 기본 선택에서 빠진다', () {
    final photos = [
      photo('a', 9, '32060'),
      LocalPhoto(assetId: 'x', takenAt: DateTime(2026, 10, 3), regionId: null),
    ];
    expect(defaultSelection(photos, perRegion: 6), {'a'});
  });

  test('여행 조각이 주어지면 그 조각의 사진만 기본 선택한다', () {
    final photos = [photo('a', 9, '32060'), photo('b', 10, '11140')];
    expect(defaultSelection(photos, regions: {'32060'}), {'a'});
  });
}
