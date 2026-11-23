import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

import '../../core/result/result.dart';
import '../../features/scan/photo_days.dart';
import '../../map_data/map_asset.dart';

typedef PhotoScan = ({int total, List<PhotoMeta> located});

// 사진첩 메타데이터만 읽는다. iOS는 PHAsset.location을 쓰므로 원본을 열지 않고,
// iCloud에만 있는 사진도 포함된다(설계 5.1)
class PhotoLibraryRepository {
  const PhotoLibraryRepository();

  static const pageSize = 500;

  // 권한 창을 띄우지 않고 전체 접근 여부만 확인한다
  Future<bool> hasFullAccess() async =>
      await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      ) ==
      PermissionState.authorized;

  // 스캔 구간은 이전 상한을 제외한다. 기기마다 다른 날짜 정밀도에도 빈 구간이 없다.
  Future<Result<PhotoScan>> readLocatedPhotos({
    DateTime? since,
    DateTime? until,
  }) async {
    final permission = await PhotoManager.requestPermissionExtend();
    // 선택한 사진만 허용한 상태에서는 자동 채우기가 동작하지 않는다
    if (permission != PermissionState.authorized) {
      return const Err(AppError.photoPermission);
    }
    return guard(() async {
      final end = (until ?? DateTime.now()).toUtc();
      final start = since?.toUtc();
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
        filterOption: AdvancedCustomFilter(
          where: [
            if (start != null)
              DateColumnWhereCondition(
                column: CustomColumns.base.createDate,
                operator: '>',
                value: start,
              ),
            DateColumnWhereCondition(
              column: CustomColumns.base.createDate,
              operator: '<=',
              value: end,
            ),
          ],
        ),
      );
      if (paths.isEmpty) return (total: 0, located: <PhotoMeta>[]);
      final all = paths.single;
      final total = await all.assetCountAsync;
      final located = <PhotoMeta>[];
      for (var page = 0; page * pageSize < total; page++) {
        for (final asset in await all.getAssetListPaged(
          page: page,
          size: pageSize,
        )) {
          final lat = asset.latitude;
          final lon = asset.longitude;
          if (lat == null || lon == null || (lat == 0 && lon == 0)) continue;
          located.add(PhotoMeta(asset.createDateTime, GeoPoint(lon, lat)));
        }
      }
      return (total: total, located: located);
    });
  }

  // 여행 기간에 찍힌 내 사진(설계 8.0). 위치가 없는 사진도 포함한다
  Future<Result<List<({String id, DateTime takenAt, GeoPoint? location})>>>
  photosInRange(DateTime start, DateTime endInclusive) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (permission != PermissionState.authorized) {
      return const Err(AppError.photoPermission);
    }
    return guard(() async {
      final end = DateTime(
        endInclusive.year,
        endInclusive.month,
        endInclusive.day + 1,
      );
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          createTimeCond: DateTimeCond(
            min: start,
            max: end.subtract(const Duration(milliseconds: 1)),
          ),
        ),
      );
      if (paths.isEmpty) return const [];
      final all = paths.single;
      final assets = await all.getAssetListRange(
        start: 0,
        end: await all.assetCountAsync,
      );
      return [
        for (final asset in assets)
          (
            id: asset.id,
            takenAt: asset.createDateTime,
            location:
                asset.latitude == null ||
                    asset.longitude == null ||
                    (asset.latitude == 0 && asset.longitude == 0)
                ? null
                : GeoPoint(asset.longitude!, asset.latitude!),
          ),
      ];
    });
  }

  // 사진첩 전체를 최신순으로 한 쪽씩 읽는다. 날짜가 여행과 다른 사진을 고를 때 쓴다
  Future<Result<List<({String id, DateTime takenAt, GeoPoint? location})>>>
  recentPhotos({required int page, required int size}) async {
    final permission = await PhotoManager.requestPermissionExtend();
    if (permission != PermissionState.authorized) {
      return const Err(AppError.photoPermission);
    }
    return guard(() async {
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );
      if (paths.isEmpty) return const [];
      return [
        for (final asset in await paths.single.getAssetListPaged(
          page: page,
          size: size,
        ))
          (
            id: asset.id,
            takenAt: asset.createDateTime,
            location: _locationOf(asset),
          ),
      ];
    });
  }

  // 원본(EXIF 포함). iCloud에만 있으면 내려받는다. 업로드 전에 재인코딩해 메타데이터를 지운다
  Future<Uint8List?> originalBytes(
    String assetId,
    PMCancelToken cancelToken,
  ) async => (await AssetEntity.fromId(
    assetId,
  ))?.getOriginBytes(cancelToken: cancelToken);

  // iCloud에만 있는 원본을 미리 내려받아 기기에 두게 한다. 한 번 받으면 다음 읽기는
  // 바로 끝난다(2026-11-20 실기기 측정: iCloud 원본 읽기 최대 2.7초, 기기 원본 0.01초).
  // 받은 바이트는 들고 있지 않는다
  Future<void> prefetchOriginal(
    String assetId,
    PMCancelToken cancelToken,
  ) async {
    final asset = await AssetEntity.fromId(assetId);
    if (asset == null || await asset.isLocallyAvailable(isOrigin: true)) return;
    await asset.getOriginBytes(cancelToken: cancelToken);
  }

  static GeoPoint? _locationOf(AssetEntity asset) {
    final lat = asset.latitude;
    final lon = asset.longitude;
    if (lat == null || lon == null || (lat == 0 && lon == 0)) return null;
    return GeoPoint(lon, lat);
  }
}
