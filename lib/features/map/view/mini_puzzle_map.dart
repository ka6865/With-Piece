import 'package:flutter/material.dart';

import '../../../map_data/map_asset.dart';
import '../painter/puzzle_layout.dart';
import '../painter/puzzle_painter.dart';

// 홈 카드의 작은 전국 지도. 조각 229개를 그대로 그려 채운 수와 화면이 어긋나지
// 않게 한다(커플 디자인 4.2). 탭 판정과 확대가 없어 PuzzleMap 대신 페인터만 쓴다
class MiniPuzzleMap extends StatefulWidget {
  const MiniPuzzleMap({
    super.key,
    required this.asset,
    required this.visitedRegionIds,
    this.homeRegionIds = const {},
    this.snapRegionIds = const {},
  });

  static const snapDuration = Duration(milliseconds: 700);

  final MapAsset asset;
  final Set<String> visitedRegionIds;
  final Set<String> homeRegionIds;
  // 새로 채운 조각. 위에서 내려와 제자리에 맞춰진다(커플 디자인 4.7)
  final Set<String> snapRegionIds;

  @override
  State<MiniPuzzleMap> createState() => _MiniPuzzleMapState();
}

class _MiniPuzzleMapState extends State<MiniPuzzleMap>
    with SingleTickerProviderStateMixin {
  PuzzleLayout? _layout;
  MapAsset? _layoutAsset;

  late final AnimationController _snap;

  @override
  void initState() {
    super.initState();
    _snap = AnimationController(
      vsync: this,
      duration: MiniPuzzleMap.snapDuration,
    );
    if (widget.snapRegionIds.isNotEmpty) _snap.forward();
  }

  @override
  void didUpdateWidget(MiniPuzzleMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapRegionIds, widget.snapRegionIds) &&
        widget.snapRegionIds.isNotEmpty) {
      _snap.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _snap.dispose();
    super.dispose();
  }

  // 애셋이나 크기가 바뀔 때만 화면 좌표를 다시 계산한다
  PuzzleLayout _layoutFor(Size size) {
    final cached = _layout;
    if (cached != null &&
        identical(_layoutAsset, widget.asset) &&
        cached.size == size) {
      return cached;
    }
    _layoutAsset = widget.asset;
    return _layout = PuzzleLayout.build(asset: widget.asset, size: size);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final layout = _layoutFor(constraints.biggest);
      final scheme = Theme.of(context).colorScheme;
      final snap = widget.snapRegionIds;
      return ExcludeSemantics(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 맞춰 넣는 조각은 아래 지도에서 빈 조각으로 두고 위 레이어에서만 그린다
            CustomPaint(
              painter: PuzzlePainter(
                layout: layout,
                visitedRegionIds: widget.visitedRegionIds.difference(snap),
                homeRegionIds: widget.homeRegionIds.difference(snap),
                regionNames: const {},
                colorScheme: scheme,
                compact: true,
              ),
            ),
            if (snap.isNotEmpty)
              RepaintBoundary(
                child: CustomPaint(
                  painter: _SnapPainter(
                    animation: _snap,
                    layout: layout,
                    regionIds: snap,
                    visitedRegionIds: widget.visitedRegionIds,
                    homeRegionIds: widget.homeRegionIds,
                    colorScheme: scheme,
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

// 새 조각만 다시 그리는 레이어. 지도 전체는 애니메이션 동안 다시 그리지 않는다
class _SnapPainter extends CustomPainter {
  _SnapPainter({
    required this.animation,
    required this.layout,
    required this.regionIds,
    required this.visitedRegionIds,
    required this.homeRegionIds,
    required this.colorScheme,
  }) : super(repaint: animation);

  static const startScale = 1.4;
  static const lift = 12.0;

  final Animation<double> animation;
  final PuzzleLayout layout;
  final Set<String> regionIds;
  final Set<String> visitedRegionIds;
  final Set<String> homeRegionIds;
  final ColorScheme colorScheme;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutBack.transform(animation.value);
    final scale = startScale + (1 - startScale) * t;
    // 앞부분에서 빠르게 나타나고 나머지 시간은 맞춰지는 움직임에 쓴다
    final alpha = (animation.value * 2.5).clamp(0.0, 1.0);
    for (final id in regionIds) {
      final polygons = [
        for (final p in layout.polygons)
          if (p.regionId == id) p,
      ];
      if (polygons.isEmpty) continue;
      final center = polygons
          .map((p) => p.bounds)
          .reduce((a, b) => a.expandToInclude(b))
          .center;
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
      canvas
        ..translate(center.dx, center.dy - lift * (1 - t))
        ..scale(scale)
        ..translate(-center.dx, -center.dy);
      PuzzlePainter(
        layout: PuzzleLayout(
          size: layout.size,
          polygons: polygons,
          insetRects: const {},
          insetRegionIds: const {},
          labelPoints: const {},
        ),
        visitedRegionIds: visitedRegionIds,
        homeRegionIds: homeRegionIds,
        regionNames: const {},
        colorScheme: colorScheme,
        compact: true,
      ).paint(canvas, size);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SnapPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.regionIds != regionIds ||
      oldDelegate.visitedRegionIds != visitedRegionIds ||
      oldDelegate.homeRegionIds != homeRegionIds ||
      oldDelegate.colorScheme != colorScheme;
}
