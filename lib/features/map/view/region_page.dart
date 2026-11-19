import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/result/result.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../data/repositories/repository_providers.dart';
import '../../../data/repositories/trip_repository.dart';
import '../../../map_data/map_asset_loader.dart';
import '../../album/album_providers.dart';
import '../../album/photo_grid.dart';
import '../../auth/auth_state.dart';
import '../../scan/scan_providers.dart';
import '../../trip/trip_candidates_page.dart';
import '../painter/cover_fit.dart';
import '../painter/puzzle_layout.dart';
import '../painter/puzzle_painter.dart';
import '../region_covers.dart';
import 'province_map_page.dart';

// 그 조각의 사진(여행 구분 없이), 촬영 순
List<PhotoRecord> _regionPhotos(Iterable<PhotoRecord> photos, String regionId) {
  final list = [...photos.where((p) => p.regionId == regionId)];
  list.sort((a, b) {
    final at = a.takenAt, bt = b.takenAt;
    if (at == null || bt == null) return at == null ? 1 : -1;
    return at.compareTo(bt);
  });
  return list;
}

// 시도 화면에서 채운 조각을 누르면 여는 화면. 맨 위 대표 사진 바꾸기, 그 아래 그 조각이
// 들어간 여행(앨범)들. 생활권이면 그 조각의 사진도 모아 보인다(설계 4.3)
class RegionPage extends ConsumerWidget {
  const RegionPage({super.key, required this.regionId});

  final String regionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(currentCoupleScopeProvider);
    final names = ref.watch(regionNamesProvider).value ?? const {};
    final trips = [
      ...?(scope == null ? null : ref.watch(scopedTripsProvider(scope)).value)
          ?.where(
            (t) =>
                t.status == TripStatus.confirmed &&
                t.regionIds.contains(regionId),
          ),
    ]..sort((a, b) => a.range.start.compareTo(b.range.start));
    final home =
        scope != null &&
        (ref
                .watch(scopedHomeRegionIdsProvider(scope))
                .value
                ?.contains(regionId) ??
            false);
    final photos = _regionPhotos(
      (scope == null
              ? null
              : ref.watch(scopedCouplePhotosProvider(scope)).value) ??
          const [],
      regionId,
    );
    return Scaffold(
      appBar: AppBar(title: Text(names[regionId] ?? regionId)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (photos.isNotEmpty)
            FilledButton.tonalIcon(
              onPressed: () => context.push('/regions/$regionId/cover'),
              icon: const Icon(Icons.photo_outlined),
              label: const Text('대표 사진 바꾸기'),
            ),
          for (final trip in trips)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: ListTile(
                leading: const Icon(Icons.photo_album_outlined),
                title: Text(trip.title),
                subtitle: Text(formatRange(trip.range)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/trips/${trip.id}'),
              ),
            ),
          if (home) ...[
            Padding(
              padding: const EdgeInsets.only(top: 24, bottom: 8),
              child: Text(
                '생활권에서 찍은 사진',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            PhotoGrid(photos: photos),
          ],
        ],
      ),
    );
  }
}

// 그 조각의 사진을 여행 구분 없이 모아 대표 사진을 고른다
class CoverPickerPage extends ConsumerWidget {
  const CoverPickerPage({super.key, required this.regionId});

  final String regionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(currentCoupleScopeProvider);
    final photos = _regionPhotos(
      (scope == null
              ? null
              : ref.watch(scopedCouplePhotosProvider(scope)).value) ??
          const [],
      regionId,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('대표 사진 고르기')),
      body: photos.isEmpty
          ? const Center(child: Text('이 조각에 올린 사진이 없어요'))
          : FutureBuilder<Map<String, String>>(
              key: ValueKey(scope),
              future: ref.watch(signedUrlCacheProvider).urls([
                for (final p in photos) p.thumbPath,
              ]),
              builder: (context, urls) => GridView.count(
                padding: const EdgeInsets.all(4),
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                children: [
                  for (final photo in photos)
                    Semantics(
                      button: true,
                      label: '이 사진으로 정하기',
                      child: GestureDetector(
                        onTap: () async {
                          final saved = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => CoverCropPage(
                                regionId: regionId,
                                photo: photo,
                              ),
                            ),
                          );
                          if (saved == true && context.mounted) context.pop();
                        },
                        child: RemoteImage(url: urls.data?[photo.thumbPath]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// 조각 모양 틀 안에서 사진을 확대·이동해 구도를 맞춘다. 사진은 언제나 조각을 덮는다
class CoverCropPage extends ConsumerStatefulWidget {
  const CoverCropPage({super.key, required this.regionId, required this.photo});

  final String regionId;
  final PhotoRecord photo;

  @override
  ConsumerState<CoverCropPage> createState() => _CoverCropPageState();
}

class _CoverCropPageState extends ConsumerState<CoverCropPage> {
  // 틀 좌표계에서 사진을 놓은 사각형
  Rect? _placed;
  Rect? _start;
  Offset? _startFocal;
  bool _saving = false;

  Size get _image =>
      Size(widget.photo.width.toDouble(), widget.photo.height.toDouble());

  // 놓은 사각형을 저장 값으로 바꿨다가 되돌려, 조각을 덮도록 크기와 위치를 조인다
  Rect _fit(Rect bounds, Rect placed) {
    final cover = coverFromRect(
      regionId: widget.regionId,
      photoId: widget.photo.id,
      bounds: bounds,
      image: _image,
      placed: placed,
    );
    return coverImageRect(
      bounds: bounds,
      image: _image,
      scale: cover.scale,
      centerX: cover.centerX,
      centerY: cover.centerY,
    );
  }

  Future<void> _save(Rect bounds) async {
    final coupleId = ref.read(currentCoupleScopeProvider)?.coupleId;
    final placed = _placed;
    if (coupleId == null || placed == null) return;
    setState(() => _saving = true);
    final result = await ref
        .read(regionCoverRepositoryProvider)
        .save(
          coupleId,
          coverFromRect(
            regionId: widget.regionId,
            photoId: widget.photo.id,
            bounds: bounds,
            image: _image,
            placed: placed,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    ref.invalidate(regionCoversProvider);
    if (result is Ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장하지 못했어요. 잠시 뒤 다시 시도해 주세요')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final regions = ref.watch(regionMapAssetProvider).value;
    final shape = regions == null
        ? null
        : regionShapeAssetOf(regions, widget.regionId);
    final saved = ref.watch(regionCoversProvider).value?[widget.regionId];
    final url = ref.watch(_fullUrlProvider(widget.photo.fullPath)).value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth - 48;
        final layout = shape == null
            ? null
            : PuzzleLayout.build(asset: shape, size: Size(side, side));
        final bounds = layout?.polygons
            .map((p) => p.bounds)
            .reduce((a, b) => a.expandToInclude(b));
        if (bounds != null) {
          _placed ??= coverImageRect(
            bounds: bounds,
            image: _image,
            // 이미 고른 사진이면 그 구도에서 시작한다
            scale: saved?.photoId == widget.photo.id ? saved!.scale : 1,
            centerX: saved?.photoId == widget.photo.id ? saved!.centerX : 0.5,
            centerY: saved?.photoId == widget.photo.id ? saved!.centerY : 0.5,
          );
        }
        final placed = _placed;
        return Scaffold(
          appBar: AppBar(
            title: const Text('구도 맞추기'),
            actions: [
              TextButton(
                onPressed: _saving || bounds == null
                    ? null
                    : () => _save(bounds),
                child: const Text('저장'),
              ),
            ],
          ),
          body: layout == null || bounds == null || placed == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('두 손가락으로 확대하고 끌어서 조각에 보일 부분을 맞춰 주세요'),
                    ),
                    Center(
                      child: GestureDetector(
                        onScaleStart: (details) {
                          _start = _placed;
                          _startFocal = details.localFocalPoint;
                        },
                        onScaleUpdate: (details) {
                          final start = _start, focal = _startFocal;
                          if (start == null || focal == null) return;
                          final width = start.width * details.scale;
                          // 손가락 아래 사진 위 점이 손가락을 따라오게 한다
                          final anchor = (focal - start.topLeft) / start.width;
                          final topLeft =
                              details.localFocalPoint - anchor * width;
                          setState(
                            () => _placed = _fit(
                              bounds,
                              topLeft &
                                  Size(
                                    width,
                                    width * start.height / start.width,
                                  ),
                            ),
                          );
                        },
                        child: ClipRect(
                          child: SizedBox.square(
                            dimension: side,
                            child: Stack(
                              children: [
                                Positioned.fromRect(
                                  rect: placed,
                                  child: RemoteImage(url: url),
                                ),
                                CustomPaint(
                                  size: Size.square(side),
                                  painter: _FramePainter(
                                    layout: layout,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    border: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

final _fullUrlProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, path) async =>
      (await ref.watch(signedUrlCacheProvider).urls([path]))[path],
);

// 조각 바깥을 덮고 조각 테두리를 긋는다
class _FramePainter extends CustomPainter {
  const _FramePainter({
    required this.layout,
    required this.color,
    required this.border,
  });

  final PuzzleLayout layout;
  final Color color;
  final Color border;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = Path()..fillType = PathFillType.evenOdd;
    for (final polygon in layout.polygons) {
      shape.addPath(PuzzlePainter.buildPath(polygon), Offset.zero);
    }
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        shape,
      ),
      Paint()..color = color.withValues(alpha: 0.8),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.color != color ||
      oldDelegate.border != border;
}
