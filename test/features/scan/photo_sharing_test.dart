import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/photo_sharing_page.dart';

void main() {
  final day = PhotoDay(DateTime(2026, 10, 3), '32060');
  testWidgets('비교 승인은 기본 미선택이고 안내 후 고른 기록만 저장한다', (tester) async {
    Set<PhotoDay>? saved;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          photoSharingChoicesProvider.overrideWith(
            (ref) async => PhotoSharingChoices(
              coupleId: 'c1',
              days: {day: 3},
              approved: {},
              names: {'32060': '속초시'},
            ),
          ),
          savePhotoSharingProvider.overrideWithValue((coupleId, days) async {
            saved = days;
            return const Ok(null);
          }),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    expect(find.textContaining('승인한 날짜와 지역은 상대가 알아낼 수 있어요'), findsOneWidget);
    await tester.tap(find.text('속초시'));
    await tester.pump();
    await tester.tap(find.text('비교 범위 저장'));
    await tester.pumpAndSettle();
    expect(saved, {day});
  });
  testWidgets('전체 승인을 기본으로 두지 않고 기존 승인만 복원한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          photoSharingChoicesProvider.overrideWith(
            (ref) async => PhotoSharingChoices(
              coupleId: 'c1',
              days: {day: 3, PhotoDay(DateTime(2026, 10, 4), '32400'): 1},
              approved: {day},
              names: {'32060': '속초시', '32400': '고성군'},
            ),
          ),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .map((w) => w.value),
      [false, true],
    );
  });
  testWidgets('저장 실패 후 선택을 유지하고 재시도한다', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          photoSharingChoicesProvider.overrideWith(
            (ref) async => PhotoSharingChoices(
              coupleId: 'c1',
              days: {day: 3},
              approved: {},
              names: {'32060': '속초시'},
            ),
          ),
          savePhotoSharingProvider.overrideWithValue((coupleId, days) async {
            expect(coupleId, 'c1');
            calls++;
            return calls == 1 ? const Err(AppError.network) : const Ok(null);
          }),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('속초시'));
    await tester.pump();
    await tester.tap(find.text('비교 범위 저장'));
    await tester.pumpAndSettle();
    expect(find.textContaining('선택은 그대로예요'), findsOneWidget);
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      true,
    );
    await tester.tap(find.text('비교 범위 저장'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });
  testWidgets('계정 변경 중에는 이전 계정의 비교 기록을 표시하지 않는다', (tester) async {
    final controller = StreamController<PhotoSharingChoices>();
    final stream = StreamProvider<PhotoSharingChoices>(
      (ref) => controller.stream,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          photoSharingChoicesProvider.overrideWith(
            (ref) async => await ref.watch(stream.future),
          ),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    controller.add(
      PhotoSharingChoices(
        coupleId: 'a-couple',
        days: {day: 3},
        approved: {day},
        names: {'32060': 'A의 비공개 기록'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A의 비공개 기록'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PhotoSharingPage)),
    );
    container.invalidate(stream);
    container.invalidate(photoSharingChoicesProvider);
    await tester.pump();
    expect(find.text('A의 비공개 기록'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(controller.close);
  });

  testWidgets('재조회가 실패해도 이전 계정의 기록과 저장 버튼을 숨긴다', (tester) async {
    var fail = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          photoSharingChoicesProvider.overrideWith((ref) async {
            if (fail) throw AppError.permissionDenied;
            return PhotoSharingChoices(
              coupleId: 'a',
              days: {day: 1},
              approved: {day},
              names: {'32060': '이전 기록'},
            );
          }),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('이전 기록'), findsOneWidget);
    fail = true;
    ProviderScope.containerOf(
      tester.element(find.byType(PhotoSharingPage)),
    ).invalidate(photoSharingChoicesProvider);
    await tester.pump();
    await tester.pump();
    expect(find.text('이전 기록'), findsNothing);
    expect(find.text('비교 범위 저장'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('같은 커플의 다른 계정으로 바뀌면 이전 임시 선택을 버린다', (tester) async {
    var userId = 'a';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWith((ref) => userId),
          photoSharingChoicesProvider.overrideWith((ref) async {
            ref.watch(sessionUserIdProvider);
            return PhotoSharingChoices(
              coupleId: 'same-couple',
              days: {day: 3},
              approved: {},
              names: {'32060': '속초시'},
            );
          }),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('속초시'));
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      true,
    );
    userId = 'b';
    ProviderScope.containerOf(
      tester.element(find.byType(PhotoSharingPage)),
    ).invalidate(sessionUserIdProvider);
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
  });
}
