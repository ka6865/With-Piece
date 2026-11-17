import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/photo_sharing_repository.dart';

void main() {
  for (final cap in [1000, 400]) {
    test('서버 상한 $cap 에서 승인한 기록과 장수 1001행을 빠짐없이 읽는다', () async {
      final offsets = <int>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final offset = int.parse(req.uri.queryParameters['offset'] ?? '0');
        final requested = int.parse(req.uri.queryParameters['limit'] ?? '1000');
        final limit = requested < cap ? requested : cap;
        offsets.add(offset);
        final all = [
          for (var i = 0; i < 1001; i++)
            {
              'day': DateTime(
                2020,
              ).add(Duration(days: i)).toIso8601String().substring(0, 10),
              'region_id': '32060',
              'photo_days': {'photo_count': i + 1},
            },
        ];
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(all.skip(offset).take(limit).toList()));
        await req.response.close();
      });
      final client = SupabaseClient('http://127.0.0.1:${server.port}', 'test');
      try {
        final rows = (await PhotoSharingRepository(
          client,
        ).approvedWithCounts('c1')).valueOrThrow;
        expect(rows.length, 1001);
        expect(rows.values.last, 1001);
        expect(offsets, cap == 1000 ? [0, 1000, 1001] : [0, 400, 800, 1001]);
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    });
  }
}
