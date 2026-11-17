import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import '../../features/scan/home_regions.dart';
import '../../features/scan/photo_days.dart';
import '../../features/scan/trip_candidates.dart';

enum TripStatus { confirmed, dismissed }

enum TripSource { auto, manual }

class Trip {
  const Trip({
    required this.id,
    required this.title,
    required this.range,
    required this.status,
    required this.source,
    required this.regionIds,
    this.coverPhotoId,
  });

  final String id;
  final String title;
  final DateRange range;
  final TripStatus status;
  final TripSource source;
  final List<String> regionIds;
  final String? coverPhotoId;
}

// 여행 확인·버림은 RPC 한 트랜잭션으로 한다(설계 5.4)
class TripRepository {
  const TripRepository(this._client);

  final SupabaseClient _client;

  Future<Result<List<PhotoDay>>> matchedDays() => guard(() async {
    final rows = await _client.rpc('couple_matched_days') as List;
    return [
      for (final row in rows.cast<Map<String, dynamic>>())
        PhotoDay(
          DateTime.parse(row['day'] as String),
          row['region_id'] as String,
        ),
    ];
  });

  // RLS는 아카이브된 이전 커플도 읽게 열어 두므로 현재 커플로 거른다(설계 14장)
  Future<Result<List<Trip>>> trips(String coupleId) => guard(() async {
    final rows = await _client
        .from('trips')
        .select(
          'id, title, started_on, ended_on, status, source, cover_photo_id, '
          'trip_regions(region_id, created_at)',
        )
        .eq('couple_id', coupleId)
        .order('started_on', ascending: false);
    return [
      for (final row in rows)
        Trip(
          id: row['id'] as String,
          title: row['title'] as String,
          range: DateRange(
            DateTime.parse(row['started_on'] as String),
            DateTime.parse(row['ended_on'] as String),
          ),
          status: TripStatus.values.byName(row['status'] as String),
          source: TripSource.values.byName(row['source'] as String),
          coverPhotoId: row['cover_photo_id'] as String?,
          regionIds: [
            for (final r
                in (row['trip_regions'] as List).cast<Map<String, dynamic>>())
              r['region_id'] as String,
          ],
        ),
    ];
  });

  // 같은 기간 자동 여행을 두 번 확인하면 23505 → AppError.validation이다
  Future<Result<String>> confirm({
    required String title,
    required DateRange range,
    required List<String> regionIds,
    required TripSource source,
  }) => guard(
    () async =>
        await _client.rpc(
              'confirm_trip',
              params: {
                'p_title': title,
                'p_started_on': _date(range.start),
                'p_ended_on': _date(range.end),
                'p_region_ids': regionIds,
                'p_source': source.name,
              },
            )
            as String,
  );

  Future<Result<String>> dismiss(DateRange range) => guard(
    () async =>
        await _client.rpc(
              'dismiss_trip',
              params: {
                'p_started_on': _date(range.start),
                'p_ended_on': _date(range.end),
              },
            )
            as String,
  );

  Future<Result<Map<String, OverrideKind>>> overrides(String coupleId) =>
      guard(() async {
        final rows = await _client
            .from('couple_region_overrides')
            .select('region_id, kind')
            .eq('couple_id', coupleId);
        return {
          for (final row in rows)
            row['region_id'] as String: OverrideKind.values.byName(
              row['kind'] as String,
            ),
        };
      });

  // kind가 null이면 덮어쓰기를 지워 자동 분류로 돌아간다
  Future<Result<void>> setOverride(
    String coupleId,
    String regionId,
    OverrideKind? kind,
  ) => guard(() async {
    if (kind == null) {
      await _client
          .from('couple_region_overrides')
          .delete()
          .eq('couple_id', coupleId)
          .eq('region_id', regionId);
      return;
    }
    await _client.from('couple_region_overrides').upsert({
      'couple_id': coupleId,
      'region_id': regionId,
      'kind': kind.name,
      'updated_by': _client.auth.currentUser!.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });
  });

  static String _date(DateTime day) => day.toIso8601String().substring(0, 10);

  // 여행 상세의 보정(설계 5.5, 8.4). 테이블 쓰기는 RLS(활성 커플)가 막는다
  Future<Result<void>> addRegions(
    String tripId,
    String coupleId,
    Iterable<String> regionIds,
  ) => guard(
    () => _client
        .from('trip_regions')
        .upsert(
          [
            for (final id in regionIds)
              {'trip_id': tripId, 'couple_id': coupleId, 'region_id': id},
          ],
          onConflict: 'trip_id,region_id',
          ignoreDuplicates: true,
        ),
  );

  Future<Result<void>> removeRegion(String tripId, String regionId) => guard(
    () => _client
        .from('trip_regions')
        .delete()
        .eq('trip_id', tripId)
        .eq('region_id', regionId),
  );

  Future<Result<void>> rename(String tripId, String title) => guard(
    () => _client.from('trips').update({'title': title}).eq('id', tripId),
  );

  Future<Result<void>> setCover(String tripId, String? photoId) => guard(
    () => _client
        .from('trips')
        .update({'cover_photo_id': photoId})
        .eq('id', tripId),
  );
}
