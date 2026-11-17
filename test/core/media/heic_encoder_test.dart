import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/media/heic_encoder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('kr.wooripiece/heic');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return switch (call.method) {
            'encode' => Uint8List.fromList([1, 2, 3]),
            'inspect' => {'width': 400, 'height': 300, 'hasGps': false},
            _ => null,
          };
        });
  });

  test('encode는 원본·긴 변·품질을 넘기고 바이트를 받는다', () async {
    final source = Uint8List.fromList([9, 9]);
    final out = await const HeicEncoder().encode(
      source,
      maxSide: 2048,
      quality: 80,
    );
    expect(out, [1, 2, 3]);
    expect(calls.single.method, 'encode');
    expect(calls.single.arguments, {
      'source': source,
      'maxSide': 2048,
      'quality': 80,
      'format': 'heic',
    });
  });

  test('inspect는 픽셀 크기와 메타데이터 여부를 돌려준다', () async {
    final info = await const HeicEncoder().inspect(Uint8List(1));
    expect(info.width, 400);
    expect(info.height, 300);
    expect(info.hasGps, isFalse);
  });

  test('인코더가 없으면 HeicUnsupported를 던진다', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => throw PlatformException(code: 'unsupported'),
        );
    expect(
      () => const HeicEncoder().encode(Uint8List(1), maxSide: 400, quality: 80),
      throwsA(isA<HeicUnsupported>()),
    );
  });
}
