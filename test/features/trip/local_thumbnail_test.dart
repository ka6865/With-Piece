import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/trip/photo_upload_page.dart';

// 1x1 투명 PNG
final _png = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

void main() {
  testWidgets('다시 그려도 썸네일을 다시 요청하지 않고, 다시 나타나면 기억한 것을 쓴다', (tester) async {
    final original = LocalThumbnail.loader;
    addTearDown(() {
      LocalThumbnail.loader = original;
      LocalThumbnail.clearCache();
    });
    var calls = 0;
    LocalThumbnail.loader = (_) async {
      calls++;
      return _png;
    };
    Widget app(int tick, {bool show = true}) => MaterialApp(
      home: Column(
        children: [
          Text('$tick'),
          if (show)
            const SizedBox.square(
              dimension: 50,
              child: LocalThumbnail(assetId: 'a'),
            ),
        ],
      ),
    );
    await tester.pumpWidget(app(0));
    // 끌어 고르는 동안처럼 여러 번 다시 그린다
    for (var i = 1; i <= 10; i++) {
      await tester.pumpWidget(app(i));
    }
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(Image), findsOneWidget);
    // 화면 밖으로 나갔다 돌아온다
    await tester.pumpWidget(app(11, show: false));
    await tester.pumpWidget(app(12));
    expect(calls, 1);
    expect(find.byType(Image), findsOneWidget);
  });
}
