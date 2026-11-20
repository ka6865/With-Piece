import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/data/repositories/refresh_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_sharing_repository.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/scan_store.dart';
import 'package:woori_piece/features/scan/photo_sharing_page.dart';

class _SharingRepo extends PhotoSharingRepository {
  _SharingRepo(this.days)
    : super(
        SupabaseClient(
          'http://127.0.0.1:1',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
  final Map<PhotoDay, int> days;
  Map<PhotoDay, int>? approved;
  @override
  Future<Result<Map<PhotoDay, int>>> approvedWithCounts(
    String coupleId,
  ) async => Ok(Map.of(days));
  @override
  Future<Result<void>> update(
    String coupleId, {
    required Map<PhotoDay, int> approve,
    required Set<PhotoDay> revoke,
  }) async {
    approved = approve;
    return const Ok(null);
  }
}

void main() {
  final day = PhotoDay(DateTime(2026, 10, 3), '32060');
  testWidgets('비교 승인은 기본 미선택이고 안내 후 고른 기록만 저장한다', (tester) async {
    Map<PhotoDay, bool>? saved;
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
          savePhotoSharingProvider.overrideWithValue((choices, days) async {
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
    expect(saved, {day: true});
  });
  testWidgets('손대지 않은 기존 승인은 저장 변경 목록에 넣지 않는다', (tester) async {
    Map<PhotoDay, bool>? saved;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          photoSharingChoicesProvider.overrideWith(
            (ref) async => PhotoSharingChoices(
              coupleId: 'c1',
              days: {day: 3},
              approved: {day},
              names: {},
            ),
          ),
          savePhotoSharingProvider.overrideWithValue((choices, days) async {
            saved = days;
            return const Ok(null);
          }),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('비교 범위 저장'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });
  testWidgets('새 기기에서도 서버 승인과 사진 수를 표시하고 기준일 이전 승인은 숨긴다', (tester) async {
    final old = PhotoDay(DateTime(2025, 1, 1), '32060');
    final repo = _SharingRepo({day: 7, old: 9});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          currentCoupleProvider.overrideWith(
            (ref) async => Couple(
              id: 'c1',
              partnerId: 'partner',
              startedOn: DateTime(2026, 1, 1),
            ),
          ),
          scanSnapshotProvider.overrideWith(
            (ref, userId) async => ScanSnapshot({}, DateTime(2026, 11, 1)),
          ),
          regionNamesProvider.overrideWith((ref) async => {'32060': '속초시'}),
          photoSharingRepositoryProvider.overrideWithValue(repo),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    // 기준일 이전 승인은 숨겨 속초는 한 번, 하루만 남는다
    expect(find.text('1번 · 1일'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);
    await tester.tap(find.byTooltip('펼치기'));
    await tester.pumpAndSettle();
    expect(find.text('1일 · 사진 7장'), findsOneWidget);
    expect(find.text('2026.10.3'), findsOneWidget);
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((t) => t.value == true),
      isTrue,
    );
  });

  for (final success in [true, false]) {
    testWidgets('저장 중 서버 승인이 바뀌면 성공 때만 임시 변경을 초기화한다: $success', (tester) async {
      final response = Completer<Result<void>>();
      var approved = <PhotoDay>{};
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionUserIdProvider.overrideWithValue('me'),
            photoSharingChoicesProvider.overrideWith(
              (ref) async => PhotoSharingChoices(
                coupleId: 'c1',
                days: {day: 2},
                approved: approved,
                names: {'32060': '속초시'},
              ),
            ),
            savePhotoSharingProvider.overrideWithValue(
              (choices, changes) => response.future,
            ),
          ],
          child: const MaterialApp(home: PhotoSharingPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('속초시'));
      await tester.pump();
      await tester.tap(find.text('비교 범위 저장'));
      await tester.pump();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PhotoSharingPage)),
      );
      approved = {};
      container.invalidate(photoSharingChoicesProvider);
      await tester.pumpAndSettle();
      response.complete(success ? const Ok(null) : const Err(AppError.network));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        !success,
      );
    });
  }

  testWidgets('저장 중 커플이 바뀌면 새 커플에서 저장과 선택이 가능하다', (tester) async {
    var coupleId = 'c1';
    final response = Completer<Result<void>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          photoSharingChoicesProvider.overrideWith(
            (ref) async => PhotoSharingChoices(
              coupleId: coupleId,
              days: {day: 2},
              approved: {},
              names: {'32060': '속초시'},
            ),
          ),
          savePhotoSharingProvider.overrideWithValue(
            (choices, changes) => response.future,
          ),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('비교 범위 저장'));
    await tester.pump();
    coupleId = 'c2';
    ProviderScope.containerOf(
      tester.element(find.byType(PhotoSharingPage)),
    ).invalidate(photoSharingChoicesProvider);
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).onChanged,
      isNotNull,
    );
    response.complete(const Err(AppError.network));
    await tester.pumpAndSettle();
    expect(find.textContaining('저장하지 못했어요'), findsNothing);
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
          savePhotoSharingProvider.overrideWithValue((choices, days) async {
            expect(choices.coupleId, 'c1');
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

  testWidgets('고른 뒤 목록에서 빠진 날짜는 저장에서 제외하고 나머지를 저장한다', (tester) async {
    final gone = PhotoDay(DateTime(2026, 10, 4), '32400');
    final repo = _SharingRepo({});
    final refresh = _RefreshRepo();
    var days = {day: 2, gone: 1};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          photoSharingRepositoryProvider.overrideWithValue(repo),
          refreshRepositoryProvider.overrideWithValue(refresh),
          photoSharingChoicesProvider.overrideWith(
            (ref) async => PhotoSharingChoices(
              coupleId: 'c1',
              days: days,
              approved: {},
              names: const {},
            ),
          ),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.tap(find.byType(CheckboxListTile).last);
    days = {day: 2};
    ProviderScope.containerOf(
      tester.element(find.byType(PhotoSharingPage)),
    ).invalidate(photoSharingChoicesProvider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('비교 범위 저장'));
    await tester.pumpAndSettle();
    expect(repo.approved, {day: 2});
    expect(find.text('저장 중'), findsNothing);
    // 저장이 곧 최신화다
    expect(refresh.marks, 1);
  });

  testWidgets('지역 → 다녀온 번으로 묶어 고르고 사는 곳은 맨 아래에 접는다', (tester) async {
    PhotoDay jeju(int m, int d) => PhotoDay(DateTime(2025, m, d), 'jeju');
    PhotoDay osan(int d) => PhotoDay(DateTime(2025, 9, d), 'osan');
    Map<PhotoDay, bool>? saved;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          currentCoupleProvider.overrideWith(
            (ref) async =>
                const Couple(id: 'c1', partnerId: 'p', myHomeRegionId: 'osan'),
          ),
          photoSharingChoicesProvider.overrideWith(
            (ref) async => PhotoSharingChoices(
              coupleId: 'c1',
              days: {
                jeju(5, 1): 40,
                jeju(5, 2): 50,
                jeju(8, 10): 5,
                osan(1): 1,
                osan(2): 1,
              },
              approved: {},
              names: {'jeju': '제주시', 'osan': '오산시'},
            ),
          ),
          savePhotoSharingProvider.overrideWithValue((choices, days) async {
            saved = days;
            return const Ok(null);
          }),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    final titles = tester
        .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['제주시', '오산시 · 사는 곳']);
    expect(find.text('2번 · 3일'), findsOneWidget);
    // 다녀온 번 하나만 고르면 지역은 중간 상태다
    await tester.tap(find.byTooltip('펼치기').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025.5.1~2025.5.2'));
    await tester.pump();
    CheckboxListTile region() => tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '제주시'),
    );
    expect(region().value, isNull);
    // 중간 상태에서 지역을 누르면 모두 고른다
    await tester.tap(find.text('제주시'));
    await tester.pump();
    expect(region().value, isTrue);
    await tester.tap(find.text('비교 범위 저장'));
    await tester.pumpAndSettle();
    expect(saved, {jeju(5, 1): true, jeju(5, 2): true, jeju(8, 10): true});
  });

  testWidgets('같은 여행으로 붙어 다닌 조각은 한 줄로 함께 고른다', (tester) async {
    final sokcho = PhotoDay(DateTime(2025, 10, 3), 'sokcho');
    final goseong = PhotoDay(DateTime(2025, 10, 4), 'goseong');
    Map<PhotoDay, bool>? saved;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionUserIdProvider.overrideWithValue('me'),
          photoSharingChoicesProvider.overrideWith(
            (ref) async => PhotoSharingChoices(
              coupleId: 'c1',
              days: {sokcho: 30, goseong: 10},
              approved: {},
              names: {'sokcho': '속초시', 'goseong': '고성군'},
            ),
          ),
          savePhotoSharingProvider.overrideWithValue((choices, days) async {
            saved = days;
            return const Ok(null);
          }),
        ],
        child: const MaterialApp(home: PhotoSharingPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('펼치기').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2025.10.3~2025.10.4 · 고성군·속초시').first);
    await tester.pump();
    await tester.tap(find.text('비교 범위 저장'));
    await tester.pumpAndSettle();
    expect(saved, {sokcho: true, goseong: true});
  });
}

class _RefreshRepo implements RefreshRepository {
  int marks = 0;

  @override
  Future<Result<void>> markRefreshed() async {
    marks++;
    return const Ok(null);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
