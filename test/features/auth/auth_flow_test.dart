import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/app/app.dart';
import 'package:woori_piece/app/router.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/features/scan/realtime_sync.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/map_data/map_asset.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';

import 'fakes.dart';

// 테스트에서 단계를 바꿀 수 있게 한다
class StageController extends Notifier<AppStage> {
  StageController(this.initial);

  final AppStage initial;

  @override
  AppStage build() => initial;

  void set(AppStage stage) => state = stage;
}

final provinces = MapAsset.parse(
  File('assets/map/provinces_v1.json').readAsStringSync(),
);
final regions = MapAsset.parse(
  File('assets/map/regions_v1.json').readAsStringSync(),
);

Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  required AppStage stage,
  String location = '/',
  FakeAuthRepository? auth,
  FakeCoupleRepository? coupleRepository,
  Couple? couple,
  void Function()? onRealtimeStart,
}) async {
  final controller = NotifierProvider<StageController, AppStage>(
    () => StageController(stage),
  );
  final container = ProviderContainer(
    overrides: [
      sessionUserIdProvider.overrideWithValue('me'),
      appStageProvider.overrideWith((ref) => ref.watch(controller)),
      sessionProvider.overrideWith((ref) => Stream.value(null)),
      currentCoupleProvider.overrideWith((ref) async => couple),
      realtimeSyncProvider.overrideWith((ref) {
        onRealtimeStart?.call();
      }),
      initialLocationProvider.overrideWithValue(location),
      authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
      coupleRepositoryProvider.overrideWithValue(
        coupleRepository ?? FakeCoupleRepository(),
      ),
      provinceMapAssetProvider.overrideWith((ref) => provinces),
      regionMapAssetProvider.overrideWith((ref) => regions),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const WooriPieceApp(),
    ),
  );
  await tester.pumpAndSettle();
  stageOf = (s) => container.read(controller.notifier).set(s);
  return container;
}

late void Function(AppStage) stageOf;

void main() {
  testWidgets('세션이 없으면 로그인 화면', (tester) async {
    await pumpApp(tester, stage: AppStage.signedOut);
    expect(find.text('카카오로 시작하기'), findsOneWidget);
  });

  testWidgets('커플이 없으면 초대 화면', (tester) async {
    await pumpApp(tester, stage: AppStage.needsCouple);
    expect(find.text('연인과 연결하기'), findsOneWidget);
    expect(find.text('계정 설정'), findsOneWidget);
    expect(find.text('지난 기록'), findsOneWidget);
  });

  testWidgets('커플 연결 전에도 계정 설정으로 이동할 수 있다', (tester) async {
    await pumpApp(tester, stage: AppStage.needsCouple);
    await tester.tap(find.text('계정 설정'));
    await tester.pumpAndSettle();
    expect(find.text('계정 연결'), findsOneWidget);
    expect(find.text('전체 다시 스캔'), findsOneWidget);
  });

  testWidgets('설정의 사귄 날 수정 경로에서 고른 날짜를 저장한다', (tester) async {
    final couples = FakeCoupleRepository();
    await pumpApp(
      tester,
      stage: AppStage.ready,
      location: '/settings/accounts',
      coupleRepository: couples,
      couple: Couple(
        id: 'couple-1',
        partnerId: 'partner-1',
        startedOn: DateTime(2020, 1, 1),
      ),
    );
    await tester.tap(find.text('사귄 날 수정'));
    await tester.pumpAndSettle();
    expect(find.text('사귄 날 수정'), findsOneWidget);
    expect(find.text('날짜 바꾸기'), findsOneWidget);
    await tester.tap(find.text('날짜 바꾸기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(couples.startedOnCalls, [DateTime(2020, 1, 1)]);
  });

  testWidgets('세션이 없어도 앱이 전역 실시간 갱신 provider를 watch한다', (tester) async {
    var started = false;
    await pumpApp(
      tester,
      stage: AppStage.signedOut,
      onRealtimeStart: () => started = true,
    );
    expect(started, isTrue);
  });

  testWidgets('사귄 날이 없으면 사귄 날 화면', (tester) async {
    await pumpApp(tester, stage: AppStage.needsStartedOn);
    expect(find.text('언제부터 함께였나요?'), findsOneWidget);
  });

  testWidgets('커플이 아닌 단계의 계정 설정에는 하단 탭이 없다', (tester) async {
    await pumpApp(
      tester,
      stage: AppStage.needsCouple,
      location: '/settings/accounts',
    );
    expect(find.text('계정 연결'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('설정 탭에서 커플 연결이 끊기면 초대 화면으로 간다', (tester) async {
    await pumpApp(tester, stage: AppStage.ready, location: '/settings');
    expect(find.byType(NavigationBar), findsOneWidget);
    stageOf(AppStage.needsCouple);
    await tester.pumpAndSettle();
    expect(find.text('연인과 연결하기'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('커플 상태의 설정 탭에는 하단 탭이 있다', (tester) async {
    await pumpApp(tester, stage: AppStage.ready, location: '/settings');
    expect(find.text('계정 연결'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('커플이면 설정에 다시 스캔과 비교할 기록 선택이 없다', (tester) async {
    await pumpApp(
      tester,
      stage: AppStage.ready,
      location: '/settings',
      couple: Couple(
        id: 'couple-1',
        partnerId: 'partner-1',
        startedOn: DateTime(2020, 1, 1),
      ),
    );
    expect(find.text('사귄 날 수정'), findsOneWidget);
    expect(find.text('전체 다시 스캔'), findsNothing);
    expect(find.text('비교할 기록 선택'), findsNothing);
  });

  testWidgets('모두 갖추면 홈', (tester) async {
    await pumpApp(tester, stage: AppStage.ready, location: '/login');
    expect(find.text('우리의 조각'), findsOneWidget);
  });

  testWidgets('로그인 전에 받은 초대 코드를 로그인 뒤 입력칸에 채운다', (tester) async {
    await pumpApp(
      tester,
      stage: AppStage.signedOut,
      location: '/invite?code=ABCDEFGHJK',
    );
    expect(find.text('카카오로 시작하기'), findsOneWidget);
    stageOf(AppStage.needsCouple);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'ABCDEFGHJK'), findsOneWidget);
  });

  testWidgets('커플이 없는 화면은 다른 로그인 방법을 안내하고 로그아웃할 수 있다', (tester) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, stage: AppStage.needsCouple, auth: auth);
    await tester.scrollUntilVisible(
      find.textContaining('다른 방법으로 로그인했을 수 있어요'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('다른 방법으로 로그인했을 수 있어요'), findsOneWidget);
    await tester.tap(find.text('로그아웃'));
    await tester.pump();
    expect(auth.signOutCalls, 1);
  });

  testWidgets('신원이 하나뿐이면 연결 해제 버튼이 비활성이다', (tester) async {
    await pumpApp(
      tester,
      stage: AppStage.ready,
      location: '/settings/accounts',
    );
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '연결 해제'),
    );
    expect(button.onPressed, isNull);
  });
}
