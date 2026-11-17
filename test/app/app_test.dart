import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/app/app.dart';
import 'package:woori_piece/features/auth/auth_state.dart';

void main() {
  testWidgets('앱이 전국 지도 제목으로 시작한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStageProvider.overrideWithValue(AppStage.ready)],
        child: const WooriPieceApp(),
      ),
    );
    await tester.pump();
    expect(find.text('우리들의 조각'), findsOneWidget);
  });
}
