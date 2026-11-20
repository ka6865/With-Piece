import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'scan_store.dart';

Future<Directory>? _preparing;

Future<Directory> openScanDirectory() => _preparing ??= _prepareWithRetry();

Future<Directory> _prepareWithRetry() async {
  try {
    return await _prepare();
  } catch (_) {
    _preparing = null;
    rethrow;
  }
}

Future<Directory> _prepare() async {
  final documents = await getApplicationDocumentsDirectory();
  final support = await getApplicationSupportDirectory();
  final cache = await getApplicationCacheDirectory();
  await Future.wait([
    ScanStore.removeLegacyCache(documents),
    ScanStore.removeLegacyAccountCaches(support),
    if (cache.path != support.path) ScanStore.removeLegacyAccountCaches(cache),
  ]);
  if (!Platform.isAndroid && !Platform.isIOS) {
    return Directory('${cache.path}/scan_snapshots');
  }
  final path = await const MethodChannel(
    'kr.wooripiece/scan_cache',
  ).invokeMethod<String>('directory');
  if (path == null || path.isEmpty) throw StateError('기기 스캔 경로가 비어 있다');
  return Directory(path);
}
