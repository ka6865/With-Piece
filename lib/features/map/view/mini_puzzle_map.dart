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
  });

  final MapAsset asset;
  final Set<String> visitedRegionIds;
  final Set<String> homeRegionIds;

  @override
  State<MiniPuzzleMap> createState() => _MiniPuzzleMapState();
}

class _MiniPuzzleMapState extends State<MiniPuzzleMap> {
  PuzzleLayout? _layout;
  MapAsset? _layoutAsset;

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
    builder: (context, constraints) => ExcludeSemantics(
      child: CustomPaint(
        size: constraints.biggest,
        painter: PuzzlePainter(
          layout: _layoutFor(constraints.biggest),
          visitedRegionIds: widget.visitedRegionIds,
          homeRegionIds: widget.homeRegionIds,
          regionNames: const {},
          colorScheme: Theme.of(context).colorScheme,
          compact: true,
        ),
      ),
    ),
  );
}
