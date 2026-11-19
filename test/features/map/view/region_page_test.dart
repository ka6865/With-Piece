import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';
import 'package:woori_piece/data/repositories/signed_url_cache.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/album/album_providers.dart';
import 'package:woori_piece/features/auth/auth_state.dart';
import 'package:woori_piece/features/map/view/region_page.dart';
import 'package:woori_piece/features/scan/scan_providers.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';

Trip trip(String id, int day, List<String> regions) => Trip(
  id: id,
  title: '여행 $id',
  range: DateRange(DateTime(2026, 10, day), DateTime(2026, 10, day)),
  status: TripStatus.confirmed,
  source: TripSource.auto,
  regionIds: regions,
);

PhotoRecord photo(String id, String region) => PhotoRecord(
  id: id,
  tripId: 't1',
  regionId: region,
  objectKey: 'c1/t1/$id.heic',
  uploadedBy: 'me',
  takenAt: DateTime(2026, 10, 1),
  width: 4,
  height: 3,
);

Future<void> pump(
  WidgetTester tester, {
  required List<Trip> trips,
  Set<String> home = const {},
  List<PhotoRecord> photos = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('me'),
        currentCoupleProvider.overrideWith(
          (ref) async => const Couple(id: 'c1', partnerId: 'p'),
        ),
        tripsProvider.overrideWith((ref) async => trips),
        homeRegionIdsProvider.overrideWith((ref) async => home),
        couplePhotosProvider('me').overrideWith((ref) async => photos),
        regionNamesProvider.overrideWith((ref) async => {'32060': '속초시'}),
        signedUrlCacheProvider.overrideWithValue(
          SignedUrlCache((paths) async => {for (final p in paths) p: ''}),
        ),
      ],
      child: const MaterialApp(home: RegionPage(regionId: '32060')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('조각 화면은 그 조각이 들어간 여행을 날짜순으로 보인다', (tester) async {
    await pump(
      tester,
      trips: [
        trip('b', 9, ['32060']),
        trip('a', 3, ['32060', '32030']),
        trip('c', 5, ['37020']),
      ],
      photos: [photo('p1', '32060')],
    );
    expect(find.text('속초시'), findsOneWidget);
    expect(find.text('대표 사진 바꾸기'), findsOneWidget);
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((t) => (t.title as Text).data)
        .toList();
    expect(titles, ['여행 a', '여행 b']);
    expect(find.text('생활권에서 찍은 사진'), findsNothing);
  });

  testWidgets('사진이 없으면 대표 사진 바꾸기를 보이지 않는다', (tester) async {
    await pump(
      tester,
      trips: [
        trip('a', 3, ['32060']),
      ],
    );
    expect(find.text('대표 사진 바꾸기'), findsNothing);
  });

  testWidgets('생활권이면서 여행도 있으면 여행과 사진을 함께 보인다', (tester) async {
    await pump(
      tester,
      trips: [
        trip('a', 3, ['32060']),
      ],
      home: {'32060'},
      photos: [photo('p1', '32060')],
    );
    expect(find.text('여행 a'), findsOneWidget);
    expect(find.text('생활권에서 찍은 사진'), findsOneWidget);
  });

  testWidgets('그 조각 사진이 없어도 같은 여행 사진이 있으면 대표 사진을 바꿀 수 있다', (tester) async {
    await pump(
      tester,
      // photo()는 여행 t1의 사진이다
      trips: [
        trip('t1', 3, ['32060', '32010']),
      ],
      photos: [photo('p1', '32010')],
    );
    expect(find.text('대표 사진 바꾸기'), findsOneWidget);
  });
}
