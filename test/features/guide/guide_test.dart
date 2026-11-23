import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/guide/guide.dart';
import 'package:woori_piece/features/guide/help_art.dart';

void main() {
  Future<void> pump(
    WidgetTester tester,
    HelpTopic topic, {
    bool reduceMotion = false,
    ThemeMode mode = ThemeMode.light,
  }) async {
    // 작은 폰 크기에서도 그림과 설명이 넘치지 않아야 한다
    tester.view.physicalSize = const Size(375, 667) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        themeMode: mode,
        darkTheme: ThemeData.dark(),
        // 시트는 새 경로라 home이 아니라 앱 전체에 동작 줄이기를 건다
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          appBar: AppBar(actions: [HelpButton(topic: topic)]),
        ),
      ),
    );
    await tester.tap(find.byTooltip('도움말'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  for (final topic in HelpTopic.values) {
    testWidgets('${topic.title} 도움말을 그림 카드로 끝까지 넘겨 보고 닫는다', (tester) async {
      await pump(tester, topic);
      expect(find.text('${topic.title} 도움말'), findsOneWidget);
      for (final (i, step) in topic.steps.indexed) {
        expect(find.text(step.text), findsOneWidget);
        // 애니메이션 한 바퀴의 여러 장면을 그려 본다
        for (var f = 0; f < 13; f++) {
          await tester.pump(HelpArtView.period ~/ 12);
        }
        final last = i == topic.steps.length - 1;
        await tester.tap(find.text(last ? '닫기' : '다음'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.text('${topic.title} 도움말'), findsNothing);
    });
  }

  testWidgets('어두운 화면에서도 모든 그림을 그린다', (tester) async {
    await pump(tester, HelpTopic.map, mode: ThemeMode.dark);
    for (var f = 0; f < 13; f++) {
      await tester.pump(HelpArtView.period ~/ 12);
    }
    expect(find.byType(HelpArtView), findsWidgets);
  });

  testWidgets('동작 줄이기를 켜면 그림이 멈춘 장면으로 서 있다', (tester) async {
    await pump(tester, HelpTopic.album, reduceMotion: true);
    // 되풀이 애니메이션이 없으면 화면이 가라앉는다
    await tester.pumpAndSettle();
    expect(find.byType(HelpArtView), findsWidgets);
  });
}
