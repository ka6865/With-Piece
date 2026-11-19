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
  });

  static const columns = 4;
  static const gap = 2.0;

  final List<String> ids;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final Widget Function(BuildContext context, String id) itemBuilder;
  final bool enabled;

  @override
  State<DragSelectGrid> createState() => _DragSelectGridState();
}

class _DragSelectGridState extends State<DragSelectGrid> {
  final _scroll = ScrollController();
  int? _anchor;
  late bool _adding;
  Set<String> _base = const {};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // 화면 위치를 격자 칸 번호로 바꾼다. 격자 밖이면 가까운 칸으로 조인다
  int? _indexAt(Offset position, double width) {
    if (widget.ids.isEmpty) return null;
    const n = DragSelectGrid.columns, gap = DragSelectGrid.gap;
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
    builder: (context, constraints) => GestureDetector(
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
          : (details) {
              final index = _indexAt(
                details.localPosition,
                constraints.maxWidth,
              );
              if (index != null) _select(index);
            },
      onHorizontalDragEnd: (_) => _anchor = null,
      child: GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(DragSelectGrid.gap),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: DragSelectGrid.columns,
          mainAxisSpacing: DragSelectGrid.gap,
          crossAxisSpacing: DragSelectGrid.gap,
        ),
        itemCount: widget.ids.length,
        itemBuilder: (context, index) =>
            widget.itemBuilder(context, widget.ids[index]),
      ),
    ),
  );
}
