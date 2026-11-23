import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/media/heic_encoder.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';

import 'support.dart';

class FakeEncoder implements ImageEncoder {
  FakeEncoder({this.heicSupported = true, this.thumbnailHasGps = false});

  final bool heicSupported;
  final bool thumbnailHasGps;
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
  Future<HeicInfo> inspect(Uint8List image) async => HeicInfo(
    width: 2048,
    height: 1536,
    hasGps: thumbnailHasGps && image.length == 10,
  );
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

class LoseFirstCommitResponseClient extends http.BaseClient {
  final objects = <String>{};
  final rows = <String, Map<String, dynamic>>{};
  var lostStorageResponse = false;
  var lostDatabaseResponse = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.contains('/storage/v1/object/photos/')) {
      final objectPath = path.split('/storage/v1/object/photos/').last;
      if (request.method == 'POST') {
        if (!objects.add(objectPath)) {
          return _reply(request, 409, {
            'statusCode': 409,
            'error': 'Duplicate',
            'message': 'The resource already exists',
          });
        }
        if (!lostStorageResponse && objectPath.contains('/full/')) {
          lostStorageResponse = true;
          throw http.ClientException('response lost after commit', request.url);
        }
        return _reply(request, 200, {'Key': 'photos/$objectPath'});
      }
      if (request.method == 'DELETE') {
        final body = jsonDecode((request as http.Request).body) as Map;
        objects.removeWhere(
          (path) => (body['prefixes'] as List).contains(path),
        );
        return _reply(request, 200, []);
      }
    }

    if (path.endsWith('/rest/v1/photos') && request.method == 'POST') {
      final row =
          jsonDecode((request as http.Request).body) as Map<String, dynamic>;
      final id = row['id'] as String;
      if (rows.containsKey(id)) {
        return _reply(request, 409, {
          'code': '23505',
          'message': 'duplicate key value violates unique constraint',
          'details': 'Key (id)=($id) already exists.',
          'hint': null,
        });
      }
      rows[id] = row;
      if (!lostDatabaseResponse) {
        lostDatabaseResponse = true;
        throw http.ClientException('response lost after commit', request.url);
      }
      return _reply(request, 201, []);
    }
    if (path.endsWith('/rest/v1/photos') && request.method == 'GET') {
      final id = request.url.queryParameters['id']?.replaceFirst('eq.', '');
      return _reply(request, 200, [
        if (rows.containsKey(id)) {'id': id},
      ]);
    }
    throw StateError('예상하지 못한 요청: ${request.method} ${request.url}');
  }

  http.StreamedResponse _reply(
    http.BaseRequest request,
    int statusCode,
    Object body,
  ) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    statusCode,
    headers: {'content-type': 'application/json'},
    request: request,
  );
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

  test('GPS가 남은 썸네일은 저장소에 보내지 않는다', () async {
    final transport = LoseFirstCommitResponseClient();
    final client = SupabaseClient(
      'http://localhost:54321',
      'test',
      httpClient: transport,
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
    addTearDown(client.dispose);
    final result =
        await PhotoRepository(
          client,
          FakeEncoder(thumbnailHasGps: true),
        ).upload(
          coupleId: 'couple',
          tripId: 'trip',
          regionId: null,
          takenAt: null,
          original: original,
        );
    expect(result, isA<Err<String>>());
    expect(transport.objects, isEmpty);
    expect(transport.rows, isEmpty);
  });

  test('상세·썸네일을 올리고 photos 행을 넣는다', () async {
    final (client, coupleId, tripId) = await coupleWithTrip();
    final repository = PhotoRepository(client, FakeEncoder());
    final photoId = (await repository.upload(
      coupleId: coupleId,
      tripId: tripId,
      regionId: '32060',
      takenAt: DateTime(2026, 10, 3, 9),
      original: original,
    )).valueOrThrow;
    expect(
      (await repository.upload(
        id: photoId,
        coupleId: coupleId,
        tripId: tripId,
        regionId: '32060',
        takenAt: DateTime(2026, 10, 3, 9),
        original: original,
      )).valueOrThrow,
      photoId,
    );
    final row = await client.from('photos').select().eq('id', photoId).single();
    expect(row['object_key'], '$coupleId/$tripId/$photoId.heic');
    expect(row['width'], 2048);
    expect(row['byte_size'], 100);
    expect(await objectsUnder(client, '$coupleId/$tripId'), [
      'full/$photoId.heic',
      'thumb/$photoId.heic',
    ]);
    expect(
      await client.from('photos').select('id').eq('id', photoId),
      hasLength(1),
    );
  }, skip: skip);

  test('커플 사진 사용량과 서버 한도를 읽는다', () async {
    final (client, coupleId, _) = await coupleWithTrip();
    final result = await PhotoRepository(client, FakeEncoder()).usage(coupleId);
    expect(result.valueOrThrow.count, 0);
    expect(result.valueOrThrow.limit, 1000);
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

  test('Storage·삽입 응답을 잃은 뒤 같은 ID로 재시도하면 기존 사진을 보존한다', () async {
    final httpClient = LoseFirstCommitResponseClient();
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-key',
      accessToken: () async => 'test-token',
      httpClient: httpClient,
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
    addTearDown(client.dispose);
    const coupleId = 'couple-id';
    const tripId = 'trip-id';
    const photoId = '90f888df-24bd-44ad-a9a7-7583758ec129';
    final repository = PhotoRepository(client, FakeEncoder());
    Future<Result<String>> upload() => repository.upload(
      id: photoId,
      coupleId: coupleId,
      tripId: tripId,
      regionId: '32060',
      takenAt: DateTime(2026, 10, 3),
      original: original,
    );

    expect(await upload(), isA<Err<String>>());
    expect(httpClient.lostStorageResponse, isTrue);
    expect(httpClient.lostDatabaseResponse, isFalse);
    // 상세와 썸네일을 함께 올려, 한쪽 응답을 잃어도 다른 쪽은 이미 올라가 있다
    expect(httpClient.objects, hasLength(2));

    expect(await upload(), isA<Err<String>>());
    expect(httpClient.lostDatabaseResponse, isTrue);
    expect(httpClient.objects, hasLength(2));

    expect(await upload(), isA<Ok<String>>());
    expect(httpClient.rows, contains(photoId));
    expect(httpClient.objects, hasLength(2));
  });

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
