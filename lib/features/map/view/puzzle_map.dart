import 'package:flutter/material.dart';

import '../../../map_data/map_asset.dart';
import '../painter/puzzle_layout.dart';
import '../painter/puzzle_painter.dart';

class PuzzleMap extends StatefulWidget {
  const PuzzleMap({
    super.key,
    required this.asset,
    required this.visitedRegionIds,
    required this.onRegionTap,
    this.homeRegionIds = const {},
    this.onRegionLongPress,
    this.showSea = false,
    this.pieceAsset,
  });

  // 탭 판정과 지역명. pieceAsset이 있으면 이 애셋은 경계만 그린다
  final MapAsset asset;
  // 칠하는 조각 애셋. 전국 지도가 시도 대신 시군구 조각을 칠할 때 쓴다.
  // 이때 visitedRegionIds·homeRegionIds는 조각 코드다
  final MapAsset? pieceAsset;
  final Set<String> visitedRegionIds;
  final ValueChanged<String> onRegionTap;
  final Set<String> homeRegionIds;
  final ValueChanged<String>? onRegionLongPress;
  final bool showSea;

  @override
  State<PuzzleMap> createState() => _PuzzleMapState();
}

class _PuzzleMapState extends State<PuzzleMap> {
  static const maxZoom = 8.0;

  final _transform = TransformationController();
  PuzzleLayout? _layout;
  MapAsset? _layoutAsset;
  PuzzleLayout? _pieceLayout;
  MapAsset? _pieceLayoutAsset;
  late Map<String, String> _regionNames;

  // 애셋이나 캔버스 크기가 바뀔 때만 화면 좌표를 다시 계산한다
  PuzzleLayout _layoutFor(Size size) {
    final cached = _layout;
    if (cached != null &&
        identical(_layoutAsset, widget.asset) &&
        cached.size == size) {
      return cached;
    }
    _layoutAsset = widget.asset;
    _regionNames = {for (final f in widget.asset.features) f.id: f.name};
    return _layout = PuzzleLayout.build(asset: widget.asset, size: size);
  }

  // 두 애셋의 본토 bbox가 같아 같은 크기면 같은 투영이 된다
  PuzzleLayout? _pieceLayoutFor(Size size) {
    final asset = widget.pieceAsset;
    if (asset == null) return null;
    final cached = _pieceLayout;
    if (cached != null &&
        identical(_pieceLayoutAsset, asset) &&
        cached.size == size) {
      return cached;
    }
    _pieceLayoutAsset = asset;
    return _pieceLayout = PuzzleLayout.build(asset: asset, size: size);
  }

  // 경계 층의 VoiceOver는 시도 단위로 읽으므로 조각 코드를 시도 코드로 올린다
  Set<String> _provincesOf(Set<String> pieceIds) {
    final parentOf = {
      for (final f in widget.pieceAsset!.features) f.id: f.parentId,
    };
    return {for (final id in pieceIds) ?parentOf[id]};
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = _layoutFor(constraints.biggest);
      final pieceLayout = _pieceLayoutFor(constraints.biggest);
      final scheme = Theme.of(context).colorScheme;
      // 확대·이동은 그린 결과에 변환만 건다. 자식의 탭 좌표는 변환이 풀린
      // 캐시 좌표계로 들어오므로 그리기와 판정이 계속 같은 좌표를 쓴다
      return InteractiveViewer(
        transformationController: _transform,
        maxScale: maxZoom,
        child: GestureDetector(
          onTapUp: (details) {
            final id = layout.hitTester.hitTest(details.localPosition);
            if (id != null) widget.onRegionTap(id);
          },
          onLongPressStart: widget.onRegionLongPress == null
              ? null
              : (details) {
                  final id = layout.hitTester.hitTest(details.localPosition);
                  if (id != null) widget.onRegionLongPress!(id);
                },
          child: Stack(
            children: [
              if (pieceLayout != null)
                RepaintBoundary(
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      size: pieceLayout.size,
                      painter: PuzzlePainter(
                        layout: pieceLayout,
                        visitedRegionIds: widget.visitedRegionIds,
                        homeRegionIds: widget.homeRegionIds,
                        regionNames: const {},
                        colorScheme: scheme,
                        showSea: widget.showSea,
                        compact: true,
                      ),
                    ),
                  ),
                ),
              RepaintBoundary(
                child: CustomPaint(
                  size: layout.size,
                  painter: PuzzlePainter(
                    layout: layout,
                    visitedRegionIds: pieceLayout == null
                        ? widget.visitedRegionIds
                        : _provincesOf(widget.visitedRegionIds),
                    homeRegionIds: pieceLayout == null
                        ? widget.homeRegionIds
                        : const {},
                    regionNames: _regionNames,
                    colorScheme: scheme,
                    showSea: widget.showSea && pieceLayout == null,
                    bordersOnly: pieceLayout != null,
                  ),
                ),
              ),
              ValueListenableBuilder(
                valueListenable: _transform,
                builder: (context, matrix, _) => CustomPaint(
                  size: layout.size,
                  painter: MapLabelPainter(
                    layout: layout,
                    regionNames: _regionNames,
                    colorScheme: scheme,
                    zoom: matrix.getMaxScaleOnAxis(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
