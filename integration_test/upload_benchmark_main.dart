// 실기기 사진 업로드 단계별 시간 측정용 진입점(2026-11-20, 24장 30초 원인 찾기). 앱 코드가 아니다.
//   flutter build ios --release -t integration_test/upload_benchmark_main.dart --dart-define-from-file=env/cloud.json
//   xcrun devicectl device install app --device <기기> build/ios/iphoneos/Runner.app
//   xcrun devicectl device process launch --console --device <기기> kr.wooripiece.wooriPiece
// 앱에 로그인된 세션을 그대로 쓴다. 측정 파일은 커플 폴더의 benchmark/ 아래 올렸다가 바로 지운다.
// 결과는 시간·크기·개수뿐이며 사진이나 좌표는 남기지 않는다.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/media/heic_encoder.dart';
import 'package:woori_piece/core/uuid.dart';

const sampleCount = 24;
const quality = 80;
const sizes = {'full': 2048, 'thumb': 400};
const workers = 3;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Map<String, Object> report;
  try {
    report = await _measure();
  } catch (error) {
    report = {'error': '$error'};
  }
  stdout.writeln('UPLOAD_BENCHMARK ${jsonEncode(report)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Text(const JsonEncoder.withIndent('  ').convert(report)),
        ),
      ),
    ),
  );
}

Map<String, int> _stats(List<int> values) {
  if (values.isEmpty) return const {};
  final sorted = [...values]..sort();
  return {
    'min': sorted.first,
    'median': sorted[sorted.length ~/ 2],
    'max': sorted.last,
    'sum': sorted.fold(0, (a, b) => a + b),
  };
}

Future<int> _time(Future<void> Function() body) async {
  final watch = Stopwatch()..start();
  await body();
  return watch.elapsedMilliseconds;
}

Future<Map<String, Object>> _measure() async {
  await Supabase.initialize(
    url: const String.fromEnvironment('SUPABASE_URL'),
    publishableKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );
  final client = Supabase.instance.client;
  final userId = client.auth.currentUser?.id;
  if (userId == null) return {'error': 'notSignedIn'};
  final coupleId =
      (await client
              .from('users')
              .select('active_couple_id')
              .eq('id', userId)
              .single())['active_couple_id']
          as String?;
  if (coupleId == null) return {'error': 'noCouple'};

  if (await PhotoManager.requestPermissionExtend() !=
      PermissionState.authorized) {
    return {'error': 'photoPermission'};
  }
  final all = (await PhotoManager.getAssetPathList(
    type: RequestType.image,
    onlyAll: true,
  )).single;
  final assets = await all.getAssetListRange(start: 0, end: sampleCount);

  const encoder = HeicEncoder();
  final storage = client.storage.from('photos');
  final folder = '$coupleId/benchmark-${uuidV4()}';

  // 단계별 시간(한 장씩 차례로)
  final localBefore = <bool>[];
  final readMs = <int>[], originalKB = <int>[];
  final encodeFullMs = <int>[], encodeThumbMs = <int>[];
  final uploadMs = <int>[], uploadKB = <int>[];
  // 원본 대신 사진첩에 2048px로 줄인 사진을 달라고 할 때
  final resizedReadMs = <int>[], resizedKB = <int>[];
  var resizedWithGps = 0;
  final uploaded = <String>[];

  for (final asset in assets) {
    localBefore.add(await asset.isLocallyAvailable(isOrigin: true));
    Uint8List? original;
    readMs.add(await _time(() async => original = await asset.originBytes));
    if (original == null) continue;
    originalKB.add(original!.length ~/ 1024);
    late Uint8List full, thumb;
    encodeFullMs.add(
      await _time(
        () async => full = await encoder.encode(
          original!,
          maxSide: sizes['full']!,
          quality: quality,
        ),
      ),
    );
    encodeThumbMs.add(
      await _time(
        () async => thumb = await encoder.encode(
          original!,
          maxSide: sizes['thumb']!,
          quality: quality,
        ),
      ),
    );
    final id = uuidV4();
    final paths = ['$folder/full/$id.heic', '$folder/thumb/$id.heic'];
    uploadKB.add((full.length + thumb.length) ~/ 1024);
    uploadMs.add(
      await _time(
        () => Future.wait([
          storage.uploadBinary(paths[0], full),
          storage.uploadBinary(paths[1], thumb),
        ]),
      ),
    );
    uploaded.addAll(paths);

    Uint8List? resized;
    resizedReadMs.add(
      await _time(
        () async => resized = await asset.thumbnailDataWithSize(
          const ThumbnailSize(2048, 2048),
          format: ThumbnailFormat.jpeg,
          quality: 95,
        ),
      ),
    );
    if (resized != null) {
      resizedKB.add(resized!.length ~/ 1024);
      if ((await encoder.inspect(resized!)).hasGps) resizedWithGps++;
    }
  }

  // 서버 왕복 한 번(사진 행 저장과 비슷한 크기)
  final roundTripMs = <int>[
    for (var i = 0; i < 5; i++)
      await _time(
        () => client.from('users').select('id').eq('id', userId).single(),
      ),
  ];

  // 지금 앱처럼 3장씩 동시에 원본 읽기 → 변환 2번 → 업로드
  var next = 0;
  Future<void> worker() async {
    while (next < assets.length) {
      final asset = assets[next++];
      final original = await asset.originBytes;
      if (original == null) continue;
      final full = await encoder.encode(
        original,
        maxSide: sizes['full']!,
        quality: quality,
      );
      final thumb = await encoder.encode(
        original,
        maxSide: sizes['thumb']!,
        quality: quality,
      );
      final id = uuidV4();
      final paths = ['$folder/full/c$id.heic', '$folder/thumb/c$id.heic'];
      await Future.wait([
        storage.uploadBinary(paths[0], full),
        storage.uploadBinary(paths[1], thumb),
      ]);
      uploaded.addAll(paths);
    }
  }

  final concurrentMs = await _time(
    () => Future.wait([for (var i = 0; i < workers; i++) worker()]),
  );

  var removed = 0;
  for (var i = 0; i < uploaded.length; i += 100) {
    removed += (await storage.remove(
      uploaded.sublist(i, (i + 100).clamp(0, uploaded.length)),
    )).length;
  }

  return {
    'samples': assets.length,
    'originLocalBefore': localBefore.where((v) => v).length,
    'originICloudOnlyBefore': localBefore.where((v) => !v).length,
    'readOriginalMs': _stats(readMs),
    'originalKB': _stats(originalKB),
    'encodeFullMs': _stats(encodeFullMs),
    'encodeThumbMs': _stats(encodeThumbMs),
    'uploadBothMs': _stats(uploadMs),
    'uploadBothKB': _stats(uploadKB),
    'roundTripMs': _stats(roundTripMs),
    'resizedReadMs': _stats(resizedReadMs),
    'resizedKB': _stats(resizedKB),
    'resizedWithGps': resizedWithGps,
    'concurrent3TotalMs': concurrentMs,
    'uploadedObjects': uploaded.length,
    'removedObjects': removed,
  };
}
