import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/album/album_page.dart';
import '../features/album/archive_page.dart';
import '../features/album/trip_detail_page.dart';
import '../features/auth/account_links_page.dart';
import '../features/auth/auth_state.dart';
import '../features/auth/invite_page.dart';
import '../features/auth/login_page.dart';
import '../features/auth/started_on_page.dart';
import '../features/map/view/national_map_page.dart';
import '../features/map/view/province_map_page.dart';
import '../features/trip/manual_trip_page.dart';
import '../features/trip/trip_candidates_page.dart';

// 테스트가 시작 위치를 바꿀 수 있게 provider로 둔다
final initialLocationProvider = Provider<String>((ref) => '/');

const _onboarding = {'/login', '/invite', '/started-on'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(appStageProvider, (_, _) => refresh.value++);
  final router = GoRouter(
    initialLocation: ref.read(initialLocationProvider),
    refreshListenable: refresh,
    redirect: (_, state) => _redirect(ref, state.uri),
    routes: [
      GoRoute(path: '/', builder: (_, _) => const NationalMapPage()),
      GoRoute(
        path: '/province/:provinceId',
        builder: (_, state) =>
            ProvinceMapPage(provinceId: state.pathParameters['provinceId']!),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/invite', builder: (_, _) => const InvitePage()),
      GoRoute(path: '/started-on', builder: (_, _) => const StartedOnPage()),
      GoRoute(path: '/album', builder: (_, _) => const AlbumPage()),
      GoRoute(path: '/archive', builder: (_, _) => const ArchivePage()),
      GoRoute(
        path: '/archive/:coupleId',
        builder: (_, state) =>
            AlbumPage(archivedCoupleId: state.pathParameters['coupleId']),
      ),
      GoRoute(
        path: '/archive/:coupleId/trips/:tripId',
        builder: (_, state) => TripDetailPage(
          tripId: state.pathParameters['tripId']!,
          archivedCoupleId: state.pathParameters['coupleId'],
        ),
      ),
      // 고정 경로(/trips/new, /trips/candidates)는 /trips/:tripId보다 먼저 둔다.
      // go_router는 위에서부터 맞추므로 뒤에 두면 여행 id로 잡혀 상세 화면이 열린다
      GoRoute(
        path: '/trips/candidates',
        builder: (_, _) => const TripCandidatesPage(),
      ),
      GoRoute(
        path: '/trips/new',
        builder: (_, state) =>
            ManualTripPage(regionId: state.uri.queryParameters['region']!),
      ),
      GoRoute(
        path: '/trips/:tripId',
        builder: (_, state) =>
            TripDetailPage(tripId: state.pathParameters['tripId']!),
      ),
      GoRoute(
        path: '/regions/:regionId/photos',
        builder: (_, state) =>
            RegionPhotosPage(regionId: state.pathParameters['regionId']!),
      ),
      GoRoute(
        path: '/settings/accounts',
        builder: (_, _) => const AccountLinksPage(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

String? _redirect(Ref ref, Uri uri) {
  // OAuth 콜백은 supabase_flutter가 처리한다. 라우터에 들어오면 지도로 보낸다
  if (uri.host == 'login-callback' || uri.path == '/login-callback') return '/';
  final code = uri.queryParameters['code'];
  if (uri.path == '/invite' && code != null) {
    // redirect는 위젯 트리를 그리는 중에 불려 provider를 바로 바꿀 수 없다
    Future.microtask(
      () => ref.read(pendingInviteCodeProvider.notifier).set(code),
    );
  }
  final target = switch (ref.read(appStageProvider)) {
    AppStage.signedOut => '/login',
    // 커플이 없어도 설정과 지난 기록(아카이브)은 볼 수 있어야 한다(설계 14장)
    AppStage.needsCouple || AppStage.needsStartedOn
        when uri.path.startsWith('/archive') ||
            uri.path == '/settings/accounts' =>
      null,
    AppStage.needsCouple => '/invite',
    AppStage.needsStartedOn => '/started-on',
    AppStage.ready => _onboarding.contains(uri.path) ? '/' : null,
    AppStage.loading || AppStage.unavailable => null,
  };
  return target == uri.path ? null : target;
}
