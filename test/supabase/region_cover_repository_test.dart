import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/region_cover_repository.dart';

import 'photo_repository_test.dart' show FakeEncoder, coupleWithTrip;
import 'support.dart';

Future<void> main() async {
  final skip = await localStackSkipReason();

  test('대표 사진을 처음 정하고 다시 바꿔도 저장된다', () async {
    final (client, coupleId, tripId) = await coupleWithTrip();
    final photos = PhotoRepository(client, FakeEncoder());
    Future<String> upload() async => (await photos.upload(
      coupleId: coupleId,
      tripId: tripId,
      regionId: '32060',
      takenAt: DateTime(2026, 10, 3),
      original: Uint8List.fromList([1]),
    )).valueOrThrow;
    final first = await upload();
    final second = await upload();
    final covers = RegionCoverRepository(client);

    expect(
      await covers.save(
        coupleId,
        RegionCover(regionId: '32060', photoId: first, scale: 1.5),
      ),
      isA<Ok<void>>(),
    );
    expect(
      await covers.save(
        coupleId,
        RegionCover(regionId: '32060', photoId: second, centerX: 0.2),
      ),
      isA<Ok<void>>(),
    );
    final saved = (await covers.covers(coupleId)).valueOrThrow['32060']!;
    expect(saved.photoId, second);
    expect(saved.centerX, closeTo(0.2, 1e-6));
  }, skip: skip);
}
