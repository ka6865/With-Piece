import 'package:flutter/services.dart';

// 이 기기에서 HEIC를 쓸 수 없다. Android API 26~27은 JPEG로 폴백한다(설계 8.1.1)
class HeicUnsupported implements Exception {
  const HeicUnsupported();
}

class HeicInfo {
  const HeicInfo({
    required this.width,
    required this.height,
    required this.hasGps,
  });

  final int width;
  final int height;
  final bool hasGps;
}

enum ImageFormat { heic, jpeg }

abstract interface class ImageEncoder {
  Future<Uint8List> encode(
    Uint8List source, {
    required int maxSide,
    required int quality,
    ImageFormat format,
  });

  Future<HeicInfo> inspect(Uint8List image);
}

// OS 코덱으로 축소·인코딩한다. 원본 속성을 복사하지 않아 GPS와 기기 정보가 빠진다
class HeicEncoder implements ImageEncoder {
  const HeicEncoder();

  static const _channel = MethodChannel('kr.wooripiece/heic');

  @override
  Future<Uint8List> encode(
    Uint8List source, {
    required int maxSide,
    required int quality,
    ImageFormat format = ImageFormat.heic,
  }) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('encode', {
        'source': source,
        'maxSide': maxSide,
        'quality': quality,
        'format': format.name,
      });
      return bytes!;
    } on PlatformException catch (e) {
      if (e.code == 'unsupported') throw const HeicUnsupported();
      rethrow;
    }
  }

  // 업로드 전 메타데이터 제거를 확인하는 데 쓴다
  @override
  Future<HeicInfo> inspect(Uint8List image) async {
    final info = (await _channel.invokeMapMethod<String, Object?>('inspect', {
      'source': image,
    }))!;
    return HeicInfo(
      width: info['width']! as int,
      height: info['height']! as int,
      hasGps: info['hasGps']! as bool,
    );
  }
}
