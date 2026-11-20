import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../data/repositories/region_cover_repository.dart';
import 'cover_fit.dart';
import 'puzzle_layout.dart';

// 조각에 채울 대표 사진. 이미지는 그리는 쪽이 아니라 불러온 쪽이 해제한다
typedef CoverImage = ({ui.Image image, RegionCover cover});

class PuzzlePainter extends CustomPainter {
  const PuzzlePainter({
    required this.layout,
    required this.visitedRegionIds,
    required this.regionNames,
    required this.colorScheme,
    this.homeRegionIds = const {},
    this.showSea = false,
    this.compact = false,
    this.bordersOnly = false,
    this.covers = const {},
    this.onRegionTap,
  });

  static const hatchGap = 6.0;
  static const dashLength = 4.0;
  static const gapLength = 3.0;

  final PuzzleLayout layout;
  final Set<String> visitedRegionIds;
  // 생활권. 칠해졌지만 여행 조각과 빗금으로 구분한다(설계 5.3, 14장)
  final Set<String> homeRegionIds;
  final Map<String, String> regionNames;
  final ColorScheme colorScheme;
  // 전국 화면만 바다를 칠한다. 시도 화면의 조각 바깥은 이웃 시도다
  final bool showSea;
  // 홈 카드의 작은 지도. 점선이 뭉쳐 보이지 않게 빈 조각 테두리를 가는 실선으로 그린다
  final bool compact;
  // 전국 지도에서 조각 층 위에 시도 경계만 굵게 긋는다. 인셋 안은 조각 애셋과
  // 인셋 범위가 미세하게 달라 선이 어긋나므로 그리지 않는다(인셋 틀이 대신한다)
  final bool bordersOnly;
  // 시도 화면에서 채운 조각을 면 색 대신 사진으로 채운다(조각채우기·최신화·대표사진 설계 4.3)
  final Map<String, CoverImage> covers;
  final ValueChanged<String>? onRegionTap;

  static Path buildPath(ScaledPolygon polygon) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in polygon.rings) {
      path.moveTo(ring.first.dx, ring.first.dy);
      for (final point in ring.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (bordersOnly) {
      final provinceBorder = Paint()
        ..color = colorScheme.onSurfaceVariant
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      for (final polygon in layout.polygons) {
        if (polygon.insetId == null) {
          canvas.drawPath(buildPath(polygon), provinceBorder);
        }
      }
      return;
    }
    final visitedFill = Paint()..color = colorScheme.primaryContainer;
    // 미방문 조각도 옅게 채워 윤곽이 배경에 묻히지 않게 한다
    final emptyFill = Paint()..color = colorScheme.surfaceContainerHighest;
    final border = Paint()
      ..color = compact ? colorScheme.outlineVariant : colorScheme.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 0.5 : 1;
    // 채운 조각과 빈 조각의 면 색 대비가 낮아 테두리와 볼록 표시로도 구분한다(커플 디자인 4.1)
    final visitedBorder = Paint()
      ..color = colorScheme.onPrimaryContainer
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final homeBorder = Paint()
      ..color = colorScheme.tertiary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (showSea) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = seaColor(colorScheme),
      );
    }
    for (final rect in layout.insetRects.values) {
      canvas.drawRect(rect, border);
    }
    final hatch = Paint()
      ..color = colorScheme.tertiary
      ..strokeWidth = 1;
    final drawnCovers = <String>{};
    for (final polygon in layout.polygons) {
      final path = buildPath(polygon);
      final home = homeRegionIds.contains(polygon.regionId);
      final visited = home || visitedRegionIds.contains(polygon.regionId);
      final cover = visited ? covers[polygon.regionId] : null;
      if (cover == null) {
        canvas.drawPath(path, visited ? visitedFill : emptyFill);
      } else if (drawnCovers.add(polygon.regionId)) {
        _drawCover(canvas, polygon.regionId, cover);
      }
      if (visited) _drawHighlight(canvas, path, highlight);
      // 사진 위 빗금은 사진을 가린다. 사진이 있는 생활권은 민트 테두리로만 구분한다
      if (home && cover == null) {
        _drawHatch(canvas, path, polygon.bounds, hatch);
      }
      // 채움 여부를 색만으로 구분하지 않도록 미방문 조각은 점선으로 그린다
      canvas.drawPath(
        visited || compact ? path : dashed(path),
        home
            ? homeBorder
            : visited
            ? visitedBorder
            : border,
      );
    }
  }

  // 조각의 모든 폴리곤을 한 틀로 잘라 사진을 그린다. 구도 기준은 본토 쪽 폴리곤의
  // bbox다. 울릉군처럼 인셋에만 있으면 인셋 폴리곤을 쓴다
  void _drawCover(Canvas canvas, String regionId, CoverImage cover) {
    final polygons = [
      for (final p in layout.polygons)
        if (p.regionId == regionId) p,
    ];
    final mainland = polygons.where((p) => p.insetId == null).toList();
    final bounds = (mainland.isEmpty ? polygons : mainland)
        .map((p) => p.bounds)
        .reduce((a, b) => a.expandToInclude(b));
    final clip = Path()..fillType = PathFillType.evenOdd;
    for (final p in polygons) {
      clip.addPath(buildPath(p), Offset.zero);
    }
    final image = cover.image;
    final src = Size(image.width.toDouble(), image.height.toDouble());
    canvas.save();
    canvas.clipPath(clip);
    if (cover.cover.scale < 1) {
      canvas.drawPath(
        clip,
        Paint()
          ..color = cover.cover.blackBackground ? Colors.black : Colors.white,
      );
    }
    canvas.drawImageRect(
      image,
      Offset.zero & src,
      coverImageRect(
        bounds: bounds,
        image: src,
        scale: cover.cover.scale,
        centerX: cover.cover.centerX,
        centerY: cover.cover.centerY,
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();
  }

  // 조각 안쪽 왼쪽 위 가장자리에 밝은 선을 그어 살짝 볼록해 보이게 한다
  static void _drawHighlight(Canvas canvas, Path path, Paint paint) {
    canvas.save();
    canvas.clipPath(path);
    canvas.drawPath(path.shift(const Offset(0.8, 0.8)), paint);
    canvas.restore();
  }

  static void _drawHatch(Canvas canvas, Path path, Rect bounds, Paint paint) {
    canvas.save();
    canvas.clipPath(path);
    for (var x = bounds.left - bounds.height; x < bounds.right; x += hatchGap) {
      canvas.drawLine(
        Offset(x, bounds.bottom),
        Offset(x + bounds.height, bounds.top),
        paint,
      );
    }
    canvas.restore();
  }

  // 테마 표면색에 파랑을 섞어 밝은 테마는 옅은 하늘색, 어두운 테마는 남색이 된다
  static Color seaColor(ColorScheme colorScheme) => Color.alphaBlend(
    Colors.blue.withValues(alpha: 0.07),
    colorScheme.surface,
  );

  static Path dashed(Path source) {
    final result = Path();
    for (final metric in source.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dashLength + gapLength) {
        result.addPath(metric.extractPath(d, d + dashLength), Offset.zero);
      }
    }
    return result;
  }

  @override
  bool shouldRepaint(PuzzlePainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.visitedRegionIds != visitedRegionIds ||
      oldDelegate.homeRegionIds != homeRegionIds ||
      oldDelegate.regionNames != regionNames ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.showSea != showSea ||
      oldDelegate.compact != compact ||
      oldDelegate.bordersOnly != bordersOnly ||
      oldDelegate.covers != covers;

  @override
  bool shouldRebuildSemantics(PuzzlePainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.visitedRegionIds != visitedRegionIds ||
      oldDelegate.homeRegionIds != homeRegionIds ||
      oldDelegate.regionNames != regionNames ||
      oldDelegate.onRegionTap != onRegionTap;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final boundsByRegion = <String, Rect>{};
    for (final polygon in layout.polygons) {
      boundsByRegion.update(
        polygon.regionId,
        (rect) => rect.expandToInclude(polygon.bounds),
        ifAbsent: () => polygon.bounds,
      );
    }
    return [
      for (final entry in boundsByRegion.entries)
        CustomPainterSemantics(
          rect: entry.value,
          properties: SemanticsProperties(
            label:
                '${regionNames[entry.key]}, '
                '${homeRegionIds.contains(entry.key)
                    ? '생활권'
                    : visitedRegionIds.contains(entry.key)
                    ? '방문'
                    : '미방문'}',
            button: true,
            onTap: onRegionTap == null ? null : () => onRegionTap!(entry.key),
            textDirection: TextDirection.ltr,
          ),
        ),
    ];
  };
}

// 시도명 약칭 규칙(설계 문서 4.5). 시군구 이름은 이 규칙에 걸리지 않아 그대로 남는다
String shortRegionName(String name) {
  if (name.endsWith('북도') || name.endsWith('남도')) {
    return '${name[0]}${name[name.length - 2]}';
  }
  for (final suffix in ['특별자치시', '특별자치도', '특별시', '광역시', '도']) {
    if (name.endsWith(suffix)) {
      return name.substring(0, name.length - suffix.length);
    }
  }
  return name;
}

// 지역명과 인셋 캡션. 지도와 따로 그려 확대할 때 이 레이어만 다시 그리고,
// 글자 크기를 배율로 나눠 화면에서는 같은 크기로 보이게 한다
class MapLabelPainter extends CustomPainter {
  const MapLabelPainter({
    required this.layout,
    required this.regionNames,
    required this.colorScheme,
    required this.zoom,
    this.backdropRegionIds = const {},
  });

  static const screenFontSize = 10.0;
  static const insetCaptions = {'ulleung': '울릉도', 'dokdo': '독도'};

  final PuzzleLayout layout;
  final Map<String, String> regionNames;
  final ColorScheme colorScheme;
  final double zoom;
  // 사진 위 이름은 옅은 바탕을 깔아 읽히게 한다
  final Set<String> backdropRegionIds;

  double get fontSize => screenFontSize / zoom;

  @override
  void paint(Canvas canvas, Size size) {
    final style = TextStyle(
      fontSize: fontSize,
      color: colorScheme.onSurfaceVariant,
    );
    TextPainter textOf(String value) => TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    for (final MapEntry(key: id, value: point) in layout.labelPoints.entries) {
      final name = regionNames[id];
      if (name == null) continue;
      final text = textOf(shortRegionName(name));
      final topLeft = point - Offset(text.width / 2, text.height / 2);
      if (backdropRegionIds.contains(id)) {
        final pad = 2 / zoom;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            (topLeft & text.size).inflate(pad),
            Radius.circular(3 / zoom),
          ),
          Paint()..color = colorScheme.surface.withValues(alpha: 0.75),
        );
      }
      text.paint(canvas, topLeft);
    }
    for (final MapEntry(key: id, value: rect) in layout.insetRects.entries) {
      final caption = insetCaptions[id];
      if (caption == null) continue;
      textOf(caption).paint(canvas, rect.topLeft + const Offset(3, 2) / zoom);
    }
  }

  @override
  bool shouldRepaint(MapLabelPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.regionNames != regionNames ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.zoom != zoom ||
      oldDelegate.backdropRegionIds != backdropRegionIds;
}
