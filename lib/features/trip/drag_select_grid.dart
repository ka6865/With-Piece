import 'dart:async';

import 'package:flutter/material.dart';

// 사진 격자. 누르면 한 장씩, 옆으로 끌기 시작하면 끈 범위를 한꺼번에 고르거나 뺀다
// (시작한 사진이 선택돼 있었으면 빼기). 위아래로 끌면 지금처럼 스크롤된다
class DragSelectGrid extends StatefulWidget {
  const DragSelectGrid({
    super.key,
    required this.ids,
    required this.selected,
    required this.onChanged,
    required this.itemBuilder,
    this.enabled = true,
    this.columns = 4,
  });

  static const gap = 2.0;
  // 끄는 손가락이 위아래 가장자리 이 거리 안에 들어오면 그쪽으로 저절로 스크롤한다
  static const edge = 64.0;
  // 가장자리 끝에 닿았을 때 한 프레임에 움직이는 거리
  static const maxStep = 18.0;

  final List<String> ids;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final Widget Function(BuildContext context, String id) itemBuilder;
  final bool enabled;
  final int columns;

  @override
  State<DragSelectGrid> createState() => _DragSelectGridState();
}

class _DragSelectGridState extends State<DragSelectGrid> {
  final _scroll = ScrollController();
  int? _anchor;
  late bool _adding;
  Set<String> _base = const {};
  Timer? _autoScroll;
  Offset? _pointer;
  Size _viewport = Size.zero;

  @override
  void dispose() {
    _autoScroll?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // 가장자리에 가까울수록 빠르게. 가장자리 밖이면 0
  double _stepFor(double y) {
    const edge = DragSelectGrid.edge;
    if (y < edge) return -DragSelectGrid.maxStep * (1 - y / edge).clamp(0, 1);
    final fromBottom = _viewport.height - y;
    if (fromBottom < edge) {
      return DragSelectGrid.maxStep * (1 - fromBottom / edge).clamp(0, 1);
    }
    return 0;
  }

  void _drag(Offset position) {
    _pointer = position;
    final index = _indexAt(position, _viewport.width);
    if (index != null) _select(index);
    if (_stepFor(position.dy) == 0) {
      _autoScroll?.cancel();
      _autoScroll = null;
      return;
    }
    // 손가락이 가장자리에 머물러 있어도 계속 스크롤하며 범위를 넓힌다
    _autoScroll ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      final pointer = _pointer;
      if (pointer == null || !_scroll.hasClients) return;
      final step = _stepFor(pointer.dy);
      final position = _scroll.position;
      final target = (position.pixels + step).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (step == 0 || target == position.pixels) return;
      _scroll.jumpTo(target);
      final index = _indexAt(pointer, _viewport.width);
      if (index != null) _select(index);
    });
  }

  void _endDrag() {
    _anchor = null;
    _pointer = null;
    _autoScroll?.cancel();
    _autoScroll = null;
  }

  // 화면 위치를 격자 칸 번호로 바꾼다. 격자 밖이면 가까운 칸으로 조인다
  int? _indexAt(Offset position, double width) {
    if (widget.ids.isEmpty) return null;
    final n = widget.columns;
    const gap = DragSelectGrid.gap;
    final cell = (width - gap * 2 - gap * (n - 1)) / n + gap;
    final col = ((position.dx - gap) / cell).floor().clamp(0, n - 1);
    final row = ((position.dy + _scroll.offset - gap) / cell).floor();
    return (row * n + col).clamp(0, widget.ids.length - 1);
  }

  void _select(int index) {
    final anchor = _anchor;
    if (anchor == null) return;
    final from = anchor < index ? anchor : index;
    final to = anchor < index ? index : anchor;
    final range = widget.ids.sublist(from, to + 1);
    widget.onChanged(
      _adding ? {..._base, ...range} : _base.difference(range.toSet()),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      _viewport = constraints.biggest;
      return GestureDetector(
        onHorizontalDragStart: !widget.enabled
            ? null
            : (details) {
                final index = _indexAt(
                  details.localPosition,
                  constraints.maxWidth,
                );
                if (index == null) return;
                _anchor = index;
                _base = {...widget.selected};
                _adding = !_base.contains(widget.ids[index]);
                _select(index);
              },
        onHorizontalDragUpdate: !widget.enabled
            ? null
            : (details) => _drag(details.localPosition),
        onHorizontalDragEnd: (_) => _endDrag(),
        onHorizontalDragCancel: _endDrag,
        child: GridView.builder(
          controller: _scroll,
          padding: const EdgeInsets.all(DragSelectGrid.gap),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: widget.columns,
            mainAxisSpacing: DragSelectGrid.gap,
            crossAxisSpacing: DragSelectGrid.gap,
          ),
          itemCount: widget.ids.length,
          itemBuilder: (context, index) =>
              widget.itemBuilder(context, widget.ids[index]),
        ),
      );
    },
  );
}
