import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/media/heic_encoder.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';

import 'support.dart';

class FakeEncoder implements ImageEncoder {
  FakeEncoder({this.heicSupported = true});

  final bool heicSupported;
  final formats = <ImageFormat>[];

  @override
  Future<Uint8List> encode(
    Uint8List source, {
    required int maxSide,
    required int quality,
    ImageFormat format = ImageFormat.heic,
  }) async {
    if (format == ImageFormat.heic && !heicSupported) {
      throw const HeicUnsupported();
    }
    formats.add(format);
    return Uint8List.fromList(List.filled(maxSide == 400 ? 10 : 100, 7));
  }

  @override
  Future<HeicInfo> inspect(Uint8List image) async =>
      const HeicInfo(width: 2048, height: 1536, hasGps: false);
}

Future<(SupabaseClient, String, String)> coupleWithTrip() async {
  final a = await signUpLocal();
  final b = await signUpLocal();
  final couple = CoupleRepository(a);
  await CoupleRepository(
    b,
  ).join((await couple.createInvite()).valueOrThrow.code);
  final coupleId = (await couple.current()).valueOrThrow!.id;
  final tripId = (await TripRepository(a).confirm(
    title: '속초시',
    range: DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 3)),
    regionIds: ['32060'],
    source: TripSource.manual,
  )).valueOrThrow;
  return (a, coupleId, tripId);
}

Future<List<String>> objectsUnder(SupabaseClient client, String prefix) async =>
    [
      for (final size in ['full', 'thumb'])
        for (final o
            in await client.storage.from('photos').list(path: '$prefix/$size'))
          '$size/${o.name}',
    ];

Future<void> main() async {
  final skip = await localStackSkipReason();
  final original = Uint8List.fromList([1, 2, 3]);

  test('상세·썸네일을 올리고 photos 행을 넣는다', () async {
    final (client, coupleId, tripId) = await coupleWithTrip();
    final photoId = (await PhotoRepository(client, FakeEncoder()).upload(
      coupleId: coupleId,
      tripId: tripId,
      regionId: '32060',
      takenAt: DateTime(2026, 10, 3, 9),
      original: original,
    )).valueOrThrow;
    final row = await client.from('photos').select().eq('id', photoId).single();
    expect(row['object_key'], '$coupleId/$tripId/$photoId.heic');
    expect(row['width'], 2048);
    expect(row['byte_size'], 100);
    expect(await objectsUnder(client, '$coupleId/$tripId'), [
      'full/$photoId.heic',
      'thumb/$photoId.heic',
    ]);
  }, skip: skip);

  test('photos 삽입이 실패하면 방금 올린 두 객체를 지운다', () async {
    final (client, coupleId, _) = await coupleWithTrip();
    const missingTrip = '00000000-0000-0000-0000-000000000000';
    final result = await PhotoRepository(client, FakeEncoder()).upload(
      coupleId: coupleId,
      tripId: missingTrip,
      regionId: '32060',
      takenAt: null,
      original: original,
    );
    expect(result, isA<Err<String>>());
    expect(await objectsUnder(client, '$coupleId/$missingTrip'), isEmpty);
  }, skip: skip);

  test('HEIC를 쓸 수 없으면 JPEG로 올린다', () async {
    final (client, coupleId, tripId) = await coupleWithTrip();
    final encoder = FakeEncoder(heicSupported: false);
    final photoId = (await PhotoRepository(client, encoder).upload(
      coupleId: coupleId,
      tripId: tripId,
      regionId: '32060',
      takenAt: null,
      original: original,
    )).valueOrThrow;
    expect(encoder.formats, [ImageFormat.jpeg, ImageFormat.jpeg]);
    final row = await client
        .from('photos')
        .select('object_key')
        .eq('id', photoId)
        .single();
    expect(row['object_key'], endsWith('$photoId.jpg'));
  }, skip: skip);

  test('사진 목록을 읽고, 올린 사람만 행과 파일을 지운다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    final couple = CoupleRepository(a);
    await CoupleRepository(
      b,
    ).join((await couple.createInvite()).valueOrThrow.code);
    final coupleId = (await couple.current()).valueOrThrow!.id;
    final tripId = (await TripRepository(a).confirm(
      title: '속초시',
      range: DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 3)),
      regionIds: ['32060'],
      source: TripSource.manual,
    )).valueOrThrow;
    final photoId = (await PhotoRepository(a, FakeEncoder()).upload(
      coupleId: coupleId,
      tripId: tripId,
      regionId: '32060',
      takenAt: DateTime(2026, 10, 3, 9),
      original: original,
    )).valueOrThrow;

    final photos = (await PhotoRepository(
      b,
      FakeEncoder(),
    ).forCouple(coupleId)).valueOrThrow;
    expect(photos.single.id, photoId);
    expect(photos.single.tripId, tripId);
    expect(photos.single.thumbPath, '$coupleId/$tripId/thumb/$photoId.heic');

    // 상대는 지우지 못한다: 행도 파일도 남는다
    await PhotoRepository(b, FakeEncoder()).delete(photos.single);
    expect(
      (await PhotoRepository(
        a,
        FakeEncoder(),
      ).forCouple(coupleId)).valueOrThrow,
      hasLength(1),
    );
    expect(await objectsUnder(a, '$coupleId/$tripId'), hasLength(2));

    expect(
      await PhotoRepository(a, FakeEncoder()).delete(photos.single),
      isA<Ok<void>>(),
    );
    expect(
      (await PhotoRepository(
        a,
        FakeEncoder(),
      ).forCouple(coupleId)).valueOrThrow,
      isEmpty,
    );
    expect(await objectsUnder(a, '$coupleId/$tripId'), isEmpty);
  }, skip: skip);
}
