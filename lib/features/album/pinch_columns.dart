import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';

// 사진 격자를 두 손가락으로 벌리면 칸이 줄어 크게, 모으면 칸이 늘어 작게 보인다.
// 제스처 경쟁에 끼지 않도록 Listener로 손가락만 세어, 스크롤과 끌기 선택은 그대로 둔다.
// 화면 종류(kind)별로 마지막 칸 수를 기억한다
class PinchColumns extends ConsumerStatefulWidget {
  const PinchColumns({
    super.key,
    required this.kind,
    required this.defaultColumns,
    required this.builder,
  });

  static const min = 2;
  static const max = 6;
  // 처음 거리보다 이만큼 벌리거나 모으면 한 칸 바꾼다
  static const step = 1.25;

  static String prefsKey(String kind) => 'grid_columns:$kind';

  final String kind;
  final int defaultColumns;
  final Widget Function(BuildContext context, int columns) builder;

  @override
  ConsumerState<PinchColumns> createState() => _PinchColumnsState();
}

class _PinchColumnsState extends ConsumerState<PinchColumns> {
  late int _columns =
      ref
          .read(sharedPreferencesProvider)
          .getInt(PinchColumns.prefsKey(widget.kind)) ??
      widget.defaultColumns;
  final _pointers = <int, Offset>{};
  double? _base;

  double? get _distance => _pointers.length == 2
      ? (_pointers.values.first - _pointers.values.last).distance
      : null;

  void _move(PointerEvent event) {
    _pointers[event.pointer] = event.position;
    final distance = _distance;
    if (distance == null) return;
    final base = _base ??= distance;
    if (base == 0) return;
    final ratio = distance / base;
    final next = ratio >= PinchColumns.step
        ? _columns - 1
        : ratio <= 1 / PinchColumns.step
        ? _columns + 1
        : _columns;
    if (next == _columns ||
        next < PinchColumns.min ||
        next > PinchColumns.max) {
      return;
    }
    _base = distance;
    setState(() => _columns = next);
    ref
        .read(sharedPreferencesProvider)
        .setInt(PinchColumns.prefsKey(widget.kind), next);
  }

  void _up(PointerEvent event) {
    _pointers.remove(event.pointer);
    _base = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
    // 칸 사이 틈을 짚어도 손가락을 센다
    behavior: HitTestBehavior.translucent,
    onPointerDown: (e) {
      _pointers[e.pointer] = e.position;
      _base = null;
    },
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _up,
    child: widget.builder(context, _columns),
  );
}
