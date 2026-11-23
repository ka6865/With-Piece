import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/home_regions.dart';
import 'package:woori_piece/features/scan/photo_days.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';
import 'package:woori_piece/data/repositories/photo_repository.dart';

class ConfirmCall {
  ConfirmCall(this.title, this.range, this.regionIds, this.source);

  final String title;
  final DateRange range;
  final List<String> regionIds;
  final TripSource source;
}

class FakeTripRepository implements TripRepository {
  final confirms = <ConfirmCall>[];
  final dismisses = <DateRange>[];
  Result<String> confirmResult = const Ok('trip-1');

  @override
  Future<Result<String>> confirm({
    required String title,
    required DateRange range,
    required List<String> regionIds,
    required TripSource source,
  }) async {
    confirms.add(ConfirmCall(title, range, regionIds, source));
    return confirmResult;
  }

  @override
  Future<Result<String>> dismiss(DateRange range) async {
    dismisses.add(range);
    return const Ok('dismissed-1');
  }

  @override
  Future<Result<List<PhotoDay>>> matchedDays() async => const Ok([]);

  @override
  Future<Result<List<Trip>>> trips(String coupleId) async => const Ok([]);

  @override
  Future<Result<Map<String, OverrideKind>>> overrides(String coupleId) async =>
      const Ok({});

  final overrideCalls = <(String, OverrideKind?)>[];

  @override
  Future<Result<void>> setOverride(
    String coupleId,
    String regionId,
    OverrideKind? kind,
  ) async {
    overrideCalls.add((regionId, kind));
    return const Ok(null);
  }

  final added = <String>[];
  final renames = <String>[];

  @override
  Future<Result<void>> addRegions(
    String tripId,
    String coupleId,
    Iterable<String> regionIds,
  ) async {
    added.addAll(regionIds);
    return const Ok(null);
  }

  final removed = <String>[];
  final deletedTrips = <String>[];
  final deletedFiles = <String>[];

  @override
  Future<Result<void>> deleteTrip(
    String tripId,
    Iterable<PhotoRecord> myPhotos,
  ) async {
    deletedTrips.add(tripId);
    deletedFiles.addAll(myPhotos.map((p) => p.id));
    return const Ok(null);
  }

  @override
  Future<Result<void>> removeRegion(String tripId, String regionId) async {
    removed.add(regionId);
    return const Ok(null);
  }

  @override
  Future<Result<void>> rename(String tripId, String title) async {
    renames.add(title);
    return const Ok(null);
  }

  @override
  Future<Result<void>> setCover(String tripId, String? photoId) async =>
      const Ok(null);
}
