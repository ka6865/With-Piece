// 실기기 사진첩 스캔 속도 측정용 진입점(설계 5.1). 앱 코드가 아니다.
//   flutter build ios --release -t integration_test/scan_benchmark_main.dart
//   xcrun devicectl device install app --device <기기> build/ios/iphoneos/Runner.app
//   xcrun devicectl device process launch --console --device <기기> kr.wooripiece.wooriPiece
// 결과는 장수·시간·개수뿐이며 좌표는 남기지 않는다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/photo_library_repository.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/map_data/geo_region_locator.dart';
import 'package:woori_piece/map_data/map_asset.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = await _measure();
  stdout.writeln('SCAN_BENCHMARK ${jsonEncode(report)}');
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
  final setup = Stopwatch()..start();
  final locator = GeoRegionLocator(
    MapAsset.parse(await rootBundle.loadString('assets/map/regions_v1.json')),
  );
  setup.stop();

  final read = Stopwatch()..start();
  final result = await const PhotoLibraryRepository().readLocatedPhotos();
  read.stop();
  final PhotoScan scan;
  switch (result) {
    case Ok(:final value):
      scan = value;
    case Err(:final error):
      return {'error': error.name};
  }

  final locate = Stopwatch()..start();
  final days = aggregatePhotoDays(scan.located, locator);
  locate.stop();

  return {
    'totalPhotos': scan.total,
    'locatedPhotos': scan.located.length,
    'locatorSetupMs': setup.elapsedMilliseconds,
    'metadataReadMs': read.elapsedMilliseconds,
    'regionLocateMs': locate.elapsedMilliseconds,
    'photoDays': days.length,
    'distinctRegions': days.keys.map((d) => d.regionId).toSet().length,
  };
}
