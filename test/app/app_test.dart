import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/app/app.dart';
import 'package:woori_piece/features/auth/auth_state.dart';

void main() {
  testWidgets('앱이 홈과 하단 탭으로 시작한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStageProvider.overrideWithValue(AppStage.ready)],
        child: const WooriPieceApp(),
      ),
    );
    await tester.pump();
    expect(find.text('우리의 조각'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
