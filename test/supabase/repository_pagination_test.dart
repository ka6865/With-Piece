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

  setUp(() async {
    ranges = [];
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
          for (var i = 0; i < 1001; i++)
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
          for (var i = 0; i < 1001; i++)
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
          for (var i = 0; i < 1001; i++)
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
      final page = all.skip(from).take(to - from + 1).toList();
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
    expect(ranges, [(0, 999), (1000, 1999)]);
  });
}
