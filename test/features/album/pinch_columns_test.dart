import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/album/pinch_columns.dart';

void main() {
  Future<SharedPreferences> pump(WidgetTester tester, {int? saved}) async {
    SharedPreferences.setMockInitialValues({
      PinchColumns.prefsKey('album'): ?saved,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: PinchColumns(
            kind: 'album',
            defaultColumns: 3,
            builder: (context, columns) => Center(child: Text('$columns칸')),
          ),
        ),
      ),
    );
    return prefs;
  }

  var pointer = 10;
  // 화면 가운데에서 두 손가락 사이를 from에서 to로 바꾼다
  Future<void> pinch(WidgetTester tester, double from, double to) async {
    final center = tester.getCenter(find.byType(PinchColumns));
    final a = await tester.startGesture(
      center - Offset(from / 2, 0),
      pointer: pointer++,
    );
    final b = await tester.startGesture(
      center + Offset(from / 2, 0),
      pointer: pointer++,
    );
    for (var i = 1; i <= 10; i++) {
      final d = from + (to - from) * i / 10;
      await a.moveTo(center - Offset(d / 2, 0));
      await b.moveTo(center + Offset(d / 2, 0));
    }
    await a.up();
    await b.up();
    await tester.pump();
  }

  testWidgets('두 손가락을 벌리면 칸이 줄고 모으면 늘며, 기억한다', (tester) async {
    final prefs = await pump(tester);
    expect(find.text('3칸'), findsOneWidget);
    await pinch(tester, 100, 140);
    expect(find.text('2칸'), findsOneWidget);
    expect(prefs.getInt(PinchColumns.prefsKey('album')), 2);
    await pinch(tester, 200, 100);
    expect(find.text('4칸'), findsOneWidget);
  });

  testWidgets('2칸보다 줄거나 6칸보다 늘지 않고, 저장한 칸 수로 시작한다', (tester) async {
    await pump(tester, saved: 6);
    expect(find.text('6칸'), findsOneWidget);
    await pinch(tester, 200, 60);
    expect(find.text('6칸'), findsOneWidget);
    await pinch(tester, 60, 300);
    expect(find.text('2칸'), findsOneWidget);
  });

  testWidgets('한 손가락으로 끌면 칸이 바뀌지 않는다', (tester) async {
    await pump(tester);
    await tester.drag(find.byType(PinchColumns), const Offset(200, 0));
    await tester.pump();
    expect(find.text('3칸'), findsOneWidget);
  });
}
