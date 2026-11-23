import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/features/trip/drag_select_grid.dart';

void main() {
  testWidgets('끌다가 아래 가장자리에 머물면 저절로 내려가며 범위를 넓힌다', (tester) async {
    final ids = [for (var i = 0; i < 60; i++) 'p$i'];
    var selected = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => DragSelectGrid(
            ids: ids,
            selected: selected,
            onChanged: (next) => setState(() => selected = next),
            itemBuilder: (context, id) =>
                ColoredBox(key: ValueKey(id), color: Colors.grey),
          ),
        ),
      ),
    );
    final grid = tester.getRect(find.byType(DragSelectGrid));
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('p0'))),
    );
    await gesture.moveBy(const Offset(30, 0));
    await gesture.moveTo(Offset(grid.center.dx, grid.bottom - 5));
    await tester.pump();
    final before = selected.length;
    // 손가락을 가장자리에 둔 채 시간이 흐른다
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(selected.length, greaterThan(before));
    expect(selected, contains('p0'));
    await gesture.up();
    await tester.pump();
    // 손을 떼면 멈춘다
    final after = selected.length;
    await tester.pump(const Duration(milliseconds: 300));
    expect(selected.length, after);
  });

  testWidgets('칸 수를 바꿔도 끈 범위의 사진을 고른다', (tester) async {
    final ids = [for (var i = 0; i < 30; i++) 'p$i'];
    var selected = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => DragSelectGrid(
            columns: 3,
            ids: ids,
            selected: selected,
            onChanged: (next) => setState(() => selected = next),
            itemBuilder: (context, id) =>
                ColoredBox(key: ValueKey(id), color: Colors.grey),
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('p0'))),
    );
    await gesture.moveBy(const Offset(30, 0));
    // 3칸이면 p4는 둘째 줄 가운데다
    await gesture.moveTo(tester.getCenter(find.byKey(const ValueKey('p4'))));
    await gesture.up();
    await tester.pump();
    expect(selected, {'p0', 'p1', 'p2', 'p3', 'p4'});
  });
}
