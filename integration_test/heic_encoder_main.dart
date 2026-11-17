// 실기기 HEIC 인코딩 측정용 진입점(설계 8.1, 8.1.1). 앱 코드가 아니다.
//   flutter build ios --release -t integration_test/heic_encoder_main.dart
//   xcrun devicectl device install app --device <기기> build/ios/iphoneos/Runner.app
//   xcrun devicectl device process launch --console --device <기기> kr.wooripiece.wooriPiece
// 결과는 크기·시간·개수뿐이며 사진이나 좌표는 남기지 않는다.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:woori_piece/core/media/heic_encoder.dart';

const sampleCount = 20;
const quality = 80;
const sizes = {'full': 2048, 'thumb': 400};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = await _measure();
  stdout.writeln('HEIC_BENCHMARK ${jsonEncode(report)}');
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text(const JsonEncoder.withIndent('  ').convert(report)),
        ),
      ),
    ),
  );
}

Future<Map<String, Object>> _measure() async {
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
  final bytesBySize = {for (final name in sizes.keys) name: <int>[]};
  final msBySize = {for (final name in sizes.keys) name: <int>[]};
  var originalsWithGps = 0;
  var outputsWithGps = 0;
  var oversized = 0;
  var failures = 0;

  for (final asset in assets) {
    final original = await asset.originBytes;
    if (original == null) {
      failures++;
      continue;
    }
    if ((await encoder.inspect(original)).hasGps) originalsWithGps++;
    for (final MapEntry(key: name, value: maxSide) in sizes.entries) {
      final watch = Stopwatch()..start();
      try {
        final out = await encoder.encode(
          original,
          maxSide: maxSide,
          quality: quality,
        );
        watch.stop();
        final info = await encoder.inspect(out);
        bytesBySize[name]!.add(out.length);
        msBySize[name]!.add(watch.elapsedMilliseconds);
        if (info.hasGps) outputsWithGps++;
        if (max(info.width, info.height) > maxSide) oversized++;
      } on HeicUnsupported {
        failures++;
      }
    }
  }

  Map<String, int> stats(List<int> values) {
    if (values.isEmpty) return const {};
    final sorted = [...values]..sort();
    return {
      'min': sorted.first,
      'median': sorted[sorted.length ~/ 2],
      'max': sorted.last,
    };
  }

  return {
    'samples': assets.length,
    'originalsWithGps': originalsWithGps,
    'outputsWithGps': outputsWithGps,
    'oversized': oversized,
    'failures': failures,
    for (final name in sizes.keys) ...{
      '${name}KB': stats([for (final b in bytesBySize[name]!) b ~/ 1024]),
      '${name}Ms': stats(msBySize[name]!),
    },
  };
}
