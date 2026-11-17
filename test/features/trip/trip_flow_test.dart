import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'package:woori_piece/features/trip/photo_selection.dart';
import 'package:woori_piece/features/trip/photo_upload_page.dart';
import 'package:woori_piece/features/trip/trip_candidates_page.dart';
import 'package:woori_piece/features/trip/trip_discovery_banner.dart';
import 'package:woori_piece/map_data/map_asset.dart';
import 'package:woori_piece/map_data/map_asset_loader.dart';

import 'fakes.dart';

final regions = MapAsset.parse(
  File('assets/map/regions_v1.json').readAsStringSync(),
);

TripCandidate candidate(int from, int to, List<String> ids, String title) =>
    TripCandidate(
      range: DateRange(DateTime(2026, 10, from), DateTime(2026, 10, to)),
      regionIds: ids,
      title: title,
    );

Future<FakeTripRepository> pumpPage(
  WidgetTester tester,
  List<TripCandidate> candidates, {
  List<LocalPhoto> photos = const [],
}) async {
  final trips = FakeTripRepository();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tripCandidatesProvider.overrideWith((ref) async => candidates),
        tripRepositoryProvider.overrideWithValue(trips),
        regionMapAssetProvider.overrideWith((ref) => regions),
        for (final c in candidates)
          localPhotosInRangeProvider(
            c.range,
          ).overrideWith((ref) async => photos),
      ],
      child: const MaterialApp(home: TripCandidatesPage()),
    ),
  );
  await tester.pumpAndSettle();
  return trips;
}

void main() {
  testWidgets('후보 목록에 제목·기간·조각 이름이 보인다', (tester) async {
    await pumpPage(tester, [
      candidate(3, 4, ['32060', '32400'], '속초시 고성군 1박 2일'),
    ]);
    expect(find.text('속초시 고성군 1박 2일'), findsOneWidget);
    expect(find.text('2026.10.3 ~ 10.4'), findsOneWidget);
    expect(find.text('속초시 · 고성군'), findsOneWidget);
  });

  testWidgets('후보 갱신은 유효한 후보를 최신 순서로 보여준다', (tester) async {
    var current = [
      candidate(3, 4, ['32060', '32400'], '속초시 고성군 1박 2일'),
    ];
    final container = ProviderContainer(
      overrides: [
        tripCandidatesProvider.overrideWith((ref) async => current),
        regionMapAssetProvider.overrideWith((ref) => regions),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TripCandidatesPage()),
      ),
    );
    await tester.pumpAndSettle();
    current = [
      candidate(3, 4, ['32060'], '속초시 1박 2일'),
      candidate(1, 1, ['37020'], '경주시'),
    ];
    container.invalidate(tripCandidatesProvider);
    await tester.pumpAndSettle();
    expect(find.text('속초시 고성군 1박 2일'), findsNothing);
    expect(find.text('속초시 1박 2일'), findsOneWidget);
    expect(find.text('경주시'), findsNWidgets(2));
    expect(
      tester.getTopLeft(find.text('속초시 1박 2일')).dy,
      lessThan(tester.getTopLeft(find.text('경주시').first).dy),
    );
    container.dispose();
  });

  testWidgets('동일한 서버 후보 갱신은 직접 합친 초안을 유지한다', (tester) async {
    var current = [
      candidate(5, 5, ['32410'], '양양군'),
      candidate(3, 3, ['32060'], '속초시'),
    ];
    final container = ProviderContainer(
      overrides: [
        tripCandidatesProvider.overrideWith((ref) async => current),
        regionMapAssetProvider.overrideWith((ref) => regions),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TripCandidatesPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('이전 후보와 합치기'));
    await tester.pumpAndSettle();
    current = [
      candidate(5, 5, ['32410'], '양양군 새 제목'),
      candidate(3, 3, ['32060'], '속초시 새 제목'),
    ];
    container.invalidate(tripCandidatesProvider);
    await tester.pumpAndSettle();
    expect(find.text('속초시 양양군 2박 3일'), findsOneWidget);
    expect(find.text('속초시 새 제목'), findsNothing);
    container.dispose();
  });

  testWidgets('확인 시트가 열린 동안 사라진 후보는 저장하지 않는다', (tester) async {
    var current = [
      candidate(3, 4, ['32060'], '속초시 1박 2일'),
    ];
    final trips = FakeTripRepository();
    final container = ProviderContainer(
      overrides: [
        tripCandidatesProvider.overrideWith((ref) async => current),
        tripRepositoryProvider.overrideWithValue(trips),
        regionMapAssetProvider.overrideWith((ref) => regions),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: TripCandidatesPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    current = [];
    container.invalidate(tripCandidatesProvider);
    await tester.pumpAndSettle();
    await tester.tap(find.text('지도에 채우기'));
    await tester.pumpAndSettle();
    expect(trips.confirms, isEmpty);
    expect(find.text('새로 찾은 여행이 없어요'), findsOneWidget);
    expect(find.text('이 여행 후보가 최신 기록에서 사라져 확인하지 않았어요'), findsOneWidget);
    container.dispose();
  });

  testWidgets('조각을 빼고 확인하면 바뀐 조각으로 확인된다', (tester) async {
    final trips = await pumpPage(tester, [
      candidate(3, 4, ['32060', '32400'], '속초시 고성군 1박 2일'),
    ]);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, '고성군'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지도에 채우기'));
    await tester.pumpAndSettle();
    expect(trips.confirms.single.regionIds, ['32060']);
    expect(find.text('속초시 고성군 1박 2일'), findsNothing);
  });

  testWidgets('이전 후보와 합치면 기간이 이어진 하나로 확인된다', (tester) async {
    final trips = await pumpPage(tester, [
      candidate(5, 5, ['32410'], '양양군'),
      candidate(3, 3, ['32060'], '속초시'),
    ]);
    await tester.tap(find.text('이전 후보와 합치기').first);
    await tester.pumpAndSettle();
    expect(find.text('2026.10.3 ~ 10.5'), findsOneWidget);
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지도에 채우기'));
    await tester.pumpAndSettle();
    expect(
      trips.confirms.single.range,
      DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 5)),
    );
    expect(trips.confirms.single.regionIds, ['32060', '32410']);
  });

  testWidgets('버리면 기간을 남기고 목록에서 사라진다', (tester) async {
    final trips = await pumpPage(tester, [
      candidate(3, 3, ['32060'], '속초시'),
    ]);
    await tester.tap(find.text('버리기'));
    await tester.pumpAndSettle();
    expect(
      trips.dismisses.single,
      DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 3)),
    );
    expect(find.text('속초시'), findsNothing);
  });

  Future<void> pumpBanner(
    WidgetTester tester,
    Future<List<TripCandidate>> Function() load,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tripCandidatesProvider.overrideWith((ref) => load())],
        child: const MaterialApp(home: Scaffold(body: TripDiscoveryBanner())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('후보가 있으면 개수를 알린다', (tester) async {
    await pumpBanner(
      tester,
      () async => [
        candidate(3, 3, ['32060'], '속초시'),
      ],
    );
    expect(find.text('함께 간 여행 1개를 찾았어요'), findsOneWidget);
  });

  testWidgets('사진 권한이 없으면 설정 안내를 보인다', (tester) async {
    await pumpBanner(tester, () async => throw AppError.photoPermission);
    expect(find.text('설정 열기'), findsOneWidget);
  });

  testWidgets('그 밖의 오류는 지도를 가리지 않는다', (tester) async {
    await pumpBanner(tester, () async => throw AppError.network);
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('후보 카드에 그 기간·조각의 내 사진을 미리 보인다', (tester) async {
    await pumpPage(
      tester,
      [
        candidate(3, 3, ['32060'], '속초시'),
      ],
      photos: [
        LocalPhoto(
          assetId: 'a',
          takenAt: DateTime(2026, 10, 3, 9),
          regionId: '32060',
        ),
        LocalPhoto(
          assetId: 'b',
          takenAt: DateTime(2026, 10, 3, 10),
          regionId: '32060',
        ),
        LocalPhoto(
          assetId: 'c',
          takenAt: DateTime(2026, 10, 3, 11),
          regionId: '11140',
        ),
      ],
    );
    expect(find.byType(LocalThumbnail), findsNWidgets(2));
    expect(find.text('사진 2장'), findsOneWidget);
  });
}
