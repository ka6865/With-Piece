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
  });

  final MapAsset asset;
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

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = _layoutFor(constraints.biggest);
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
              RepaintBoundary(
                child: CustomPaint(
                  size: layout.size,
                  painter: PuzzlePainter(
                    layout: layout,
                    visitedRegionIds: widget.visitedRegionIds,
                    homeRegionIds: widget.homeRegionIds,
                    regionNames: _regionNames,
                    colorScheme: Theme.of(context).colorScheme,
                    showSea: widget.showSea,
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
                    colorScheme: Theme.of(context).colorScheme,
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
