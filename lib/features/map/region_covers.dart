import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/region_cover_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../album/album_providers.dart';
import '../auth/auth_state.dart';

// 현재 커플이 직접 고른 대표 사진(조각 id별). Realtime 'covers' 알림으로 다시 읽는다
final regionCoversProvider = FutureProvider<Map<String, RegionCover>>((
  ref,
) async {
  ref.watch(sessionUserIdProvider);
  final couple = await ref.watch(currentCoupleProvider.future);
  if (couple == null) return const {};
  return (await ref.watch(regionCoverRepositoryProvider).covers(couple.id))
      .valueOrThrow;
});

// 조각마다 보일 사진과 구도. 고른 사진이 있으면 그것, 없거나 지워졌으면 그 조각에서
// 가장 늦게 찍은 사진을 가운데 구도로 쓴다(설계 4.3 자동 대표). 사진이 없는 조각은 빠진다
Map<String, (PhotoRecord, RegionCover)> effectiveCovers(
  Map<String, RegionCover> saved,
  Iterable<PhotoRecord> photos,
) {
  final byId = {for (final p in photos) p.id: p};
  final latest = <String, PhotoRecord>{};
  for (final photo in photos) {
    final region = photo.regionId;
    if (region == null) continue;
    final current = latest[region];
    if (current == null || _later(photo, current)) latest[region] = photo;
  }
  return {
    for (final MapEntry(key: region, value: auto) in latest.entries)
      region: switch (byId[saved[region]?.photoId]) {
        final chosen? when chosen.regionId == region => (
          chosen,
          saved[region]!,
        ),
        _ => (auto, RegionCover(regionId: region, photoId: auto.id)),
      },
  };
}

// 촬영 시각이 없는 사진은 있는 사진보다 뒤로 미룬다. 같으면 id로 정해 두 기기가 같다
bool _later(PhotoRecord a, PhotoRecord b) {
  final at = a.takenAt, bt = b.takenAt;
  if (at == null || bt == null) {
    return at != null || (bt == null && a.id.compareTo(b.id) > 0);
  }
  return at.isAfter(bt) || (at == bt && a.id.compareTo(b.id) > 0);
}

// 시도 화면을 확대하면 조각 하나가 화면 대부분을 차지해 썸네일(400px)은 흐리다.
// 상세(2048px)를 받아 긴 변 1024px로 줄여 푼다. 메모리는 장당 약 3MB다
const coverDecodeSide = 1024;

final coverImageProvider = FutureProvider.autoDispose.family<ui.Image, String>((
  ref,
  path,
) async {
  final url = (await ref.watch(signedUrlCacheProvider).urls([path]))[path];
  if (url == null) throw AppError.unknown;
  final image = await _decode(
    ResizeImage(
      NetworkImage(url),
      width: coverDecodeSide,
      height: coverDecodeSide,
      policy: ResizeImagePolicy.fit,
    ),
  );
  ref.onDispose(image.dispose);
  return image;
});

Future<ui.Image> _decode(ImageProvider provider) {
  final completer = Completer<ui.Image>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) completer.complete(info.image.clone());
      info.dispose();
      stream.removeListener(listener);
    },
    onError: (error, stack) {
      if (!completer.isCompleted) completer.completeError(error, stack);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
