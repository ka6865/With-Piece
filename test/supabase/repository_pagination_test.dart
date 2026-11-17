import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/media/heic_encoder.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/photo_days.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late List<(int, int)> ranges;
  var serverCap = 1000;
  var total = 1001;
  var endWith416 = false;
  String? failureCode;

  setUp(() async {
    ranges = [];
    serverCap = 1000;
    total = 1001;
    endWith416 = false;
    failureCode = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain();
      final from = int.parse(request.uri.queryParameters['offset'] ?? '0');
      final limit = int.parse(request.uri.queryParameters['limit'] ?? '1000');
      final to = from + limit - 1;
      ranges.add((from, to));
      final table = request.uri.pathSegments.last;
      final List<Map<String, dynamic>> all = switch (table) {
        'photos' => [
          for (var i = 0; i < total; i++)
            {
              'id': 'photo-$i',
              'trip_id': 'trip',
              'region_id': '32060',
              'object_key': 'couple/trip/photo-$i.jpg',
              'uploaded_by': 'user',
              'taken_at': '2026-01-01T00:00:00Z',
              'width': 100,
              'height': 100,
            },
        ],
        'trips' => [
          for (var i = 0; i < total; i++)
            {
              'id': 'trip-$i',
              'title': '여행',
              'started_on': '2026-01-01',
              'ended_on': '2026-01-01',
              'status': 'confirmed',
              'source': 'manual',
              'cover_photo_id': null,
              'trip_regions': [],
            },
        ],
        'couple_matched_days' => [
          for (var i = 0; i < total; i++)
            {
              'day': DateTime(
                2024,
                1,
                1,
              ).add(Duration(days: i)).toIso8601String().substring(0, 10),
              'region_id': '32060',
            },
        ],
        _ => <Map<String, dynamic>>[],
      };
      if (failureCode != null || (endWith416 && from >= total)) {
        request.response
          ..statusCode = HttpStatus.requestedRangeNotSatisfiable
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'code': failureCode ?? 'PGRST103',
              'message': 'Requested range not satisfiable',
              'details': failureCode == null
                  ? 'An offset of $from was requested, but there are only $total rows.'
                  : 'The lower boundary must be lower than or equal to the upper boundary in the Range header.',
            }),
          );
        await request.response.close();
        return;
      }
      final requested = to - from + 1;
      final page = all
          .skip(from)
          .take(requested < serverCap ? requested : serverCap)
          .toList();
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          '$from-${from + page.length - 1}/${all.length}',
        )
        ..write(jsonEncode(page));
      await request.response.close();
    });
    client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'test-key',
    );
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('사진·여행·교집합이 1,001행 전체를 페이지 조회한다', () async {
    final photos = (await PhotoRepository(
      client,
      const HeicEncoder(),
    ).forCouple('couple')).valueOrThrow;
    expect(photos, hasLength(1001));

    ranges.clear();
    final trips = (await TripRepository(client).trips('couple')).valueOrThrow;
    expect(trips, hasLength(1001));

    ranges.clear();
    final days = (await TripRepository(client).matchedDays()).valueOrThrow;
    expect(days, hasLength(1001));
    expect(days.first, PhotoDay(DateTime(2024, 1, 1), '32060'));
    expect(ranges, [(0, 999), (1000, 1999), (1001, 2000)]);
  });
  Future<void> expectAll(int length) async {
    expect(
      (await PhotoRepository(
        client,
        const HeicEncoder(),
      ).forCouple('couple')).valueOrThrow,
      hasLength(length),
    );
    expect(
      (await TripRepository(client).trips('couple')).valueOrThrow,
      hasLength(length),
    );
    expect(
      (await TripRepository(client).matchedDays()).valueOrThrow,
      hasLength(length),
    );
  }

  for (final use416 in [false, true]) {
    test('서버 상한 400에서도 사진·여행·교집합 전체를 읽는다: 종료416=$use416', () async {
      serverCap = 400;
      endWith416 = use416;
      await expectAll(1001);
      expect(ranges, [
        for (var i = 0; i < 3; i++) ...[
          (0, 999),
          (400, 1399),
          (800, 1799),
          (1001, 2000),
        ],
      ]);
    });
    test('서버 상한과 같은 행 수와 빈 목록을 모두 처리한다: 종료416=$use416', () async {
      total = 1000;
      endWith416 = use416;
      await expectAll(1000);
      total = 0;
      await expectAll(0);
    });
  }
  test('범위 오류와 권한 오류를 빈 성공으로 숨기지 않는다', () async {
    for (final code in ['PGRST103', '42501']) {
      failureCode = code;
      expect(
        await PhotoRepository(client, const HeicEncoder()).forCouple('couple'),
        isA<Err<List<PhotoRecord>>>(),
      );
      expect(
        await TripRepository(client).trips('couple'),
        isA<Err<List<Trip>>>(),
      );
      expect(
        await TripRepository(client).matchedDays(),
        isA<Err<List<PhotoDay>>>(),
      );
    }
  });
}
