import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/media/heic_encoder.dart';
import '../../core/result/result.dart';
import '../../core/uuid.dart';
import 'fetch_all.dart';

class PhotoRecord {
  const PhotoRecord({
    required this.id,
    required this.tripId,
    required this.regionId,
    required this.objectKey,
    required this.uploadedBy,
    required this.takenAt,
    required this.width,
    required this.height,
  });

  final String id;
  final String tripId;
  final String? regionId;
  // {couple_id}/{trip_id}/{uuid}.{ext}. 실제 객체는 크기 구분을 끼운 경로다(설계 6.2)
  final String objectKey;
  final String uploadedBy;
  final DateTime? takenAt;
  final int width;
  final int height;

  String pathFor(String size) {
    final slash = objectKey.lastIndexOf('/');
    return '${objectKey.substring(0, slash)}/$size${objectKey.substring(slash)}';
  }

  String get fullPath => pathFor('full');
  String get thumbPath => pathFor('thumb');
}

// 사진은 상세(2048px)와 썸네일(400px) 두 객체로 올린다(설계 8.1, 8.2)
class PhotoRepository {
  const PhotoRepository(this._client, this._encoder);

  static const bucket = 'photos';
  static const quality = 80;
  static const sizes = {'full': 2048, 'thumb': 400};

  final SupabaseClient _client;
  final ImageEncoder _encoder;

  Future<Result<String>> upload({
    String? id,
    required String coupleId,
    required String tripId,
    required String? regionId,
    required DateTime? takenAt,
    required Uint8List original,
  }) async {
    final photoId = id ?? uuidV4();
    final Map<String, Uint8List> encoded;
    final ImageFormat format;
    try {
      (encoded, format) = await _encodeAll(original);
    } catch (error) {
      return Err(appErrorOf(error));
    }
    final ext = format == ImageFormat.heic ? 'heic' : 'jpg';
    final paths = {
      for (final size in sizes.keys)
        size: '$coupleId/$tripId/$size/$photoId.$ext',
    };
    final storage = _client.storage.from(bucket);
    final uploaded = <String>[];
    var insertAttempted = false;
    var knownInsertRejection = false;
    try {
      for (final MapEntry(key: size, value: path) in paths.entries) {
        try {
          await storage.uploadBinary(
            path,
            encoded[size]!,
            fileOptions: FileOptions(
              contentType: ext == 'heic' ? 'image/heic' : 'image/jpeg',
            ),
          );
          uploaded.add(path);
        } on StorageException catch (error) {
          if (error.statusCode != '409' || error.error != 'Duplicate') rethrow;
        }
      }
      final info = await _encoder.inspect(encoded['full']!);
      insertAttempted = true;
      try {
        await _client.from('photos').insert({
          'id': photoId,
          'trip_id': tripId,
          'couple_id': coupleId,
          'region_id': regionId,
          'object_key': '$coupleId/$tripId/$photoId.$ext',
          'width': info.width,
          'height': info.height,
          'byte_size': encoded['full']!.length,
          'taken_at': takenAt?.toUtc().toIso8601String(),
        });
      } on PostgrestException catch (error) {
        if (error.code == '23505') {
          final existing = await _client
              .from('photos')
              .select('id')
              .eq('id', photoId)
              .eq('couple_id', coupleId)
              .eq('trip_id', tripId)
              .maybeSingle();
          if (existing != null) return Ok(photoId);
          rethrow;
        }
        knownInsertRejection =
            error.code == '42501' || (error.code?.startsWith('23') == true);
        rethrow;
      }
      return Ok(photoId);
    } catch (error) {
      final mayClean = insertAttempted
          ? knownInsertRejection
          : !_isUncertain(error);
      if (mayClean && uploaded.isNotEmpty) {
        try {
          await storage.remove(uploaded);
        } catch (_) {}
      }
      return Err(appErrorOf(error));
    }
  }

  bool _isUncertain(Object error) => switch (error) {
    SocketException() || TimeoutException() => true,
    StorageException(statusCode: final statusCode?) =>
      (int.tryParse(statusCode) ?? 500) >= 500,
    StorageException() => true,
    _ => false,
  };

  Future<(Map<String, Uint8List>, ImageFormat)> _encodeAll(
    Uint8List original,
  ) async {
    Future<Map<String, Uint8List>> encodeAs(ImageFormat format) async => {
      for (final MapEntry(key: size, value: maxSide) in sizes.entries)
        size: await _encoder.encode(
          original,
          maxSide: maxSide,
          quality: quality,
          format: format,
        ),
    };
    try {
      return (await encodeAs(ImageFormat.heic), ImageFormat.heic);
    } on HeicUnsupported {
      // Android API 26~27은 HEIC를 쓸 수 없어 JPEG로 폴백한다(설계 8.1.1)
      return (await encodeAs(ImageFormat.jpeg), ImageFormat.jpeg);
    }
  }

  // 메타데이터만이라 커플 전체를 한 번에 읽는다. 앨범·상세·조각별 사진이 같이 쓴다
  Future<Result<List<PhotoRecord>>> forCouple(
    String coupleId,
  ) => guard(() async {
    final query = _client
        .from('photos')
        .select(
          'id, trip_id, region_id, object_key, uploaded_by, taken_at, width, height',
        )
        .eq('couple_id', coupleId)
        .order('taken_at')
        .order('id');
    final rows = await fetchAll((from, to) => query.range(from, to));
    return [
      for (final row in rows)
        PhotoRecord(
          id: row['id'] as String,
          tripId: row['trip_id'] as String,
          regionId: row['region_id'] as String?,
          objectKey: row['object_key'] as String,
          uploadedBy: row['uploaded_by'] as String,
          takenAt: row['taken_at'] == null
              ? null
              : DateTime.parse(row['taken_at'] as String).toLocal(),
          width: row['width'] as int,
          height: row['height'] as int,
        ),
    ];
  });

  // 올린 사람만 지운다. RLS가 막으면 오류 없이 0행이 지워지므로 지워진 행으로 확인한다
  Future<Result<void>> delete(PhotoRecord photo) => guard(() async {
    final deleted = await _client
        .from('photos')
        .delete()
        .eq('id', photo.id)
        .select('id');
    if (deleted.isEmpty) {
      throw const PostgrestException(message: 'not_owner', code: '42501');
    }
    // 파일 삭제가 실패해도 행이 없으므로 정리 작업이 지운다(설계 8.3)
    await _client.storage.from(bucket).remove([
      photo.fullPath,
      photo.thumbPath,
    ]);
  });
}
