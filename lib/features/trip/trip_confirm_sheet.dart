import 'package:flutter/material.dart';

import 'region_picker.dart';

class TripConfirmation {
  const TripConfirmation(this.title, this.regionIds);

  final String title;
  final List<String> regionIds;
}

// 확인 전에 조각을 빼거나 더하고 제목을 고친다(설계 5.4, 5.5)
Future<TripConfirmation?> showTripConfirmSheet(
  BuildContext context, {
  required String title,
  required List<String> regionIds,
  required Map<String, String> regionNames,
}) => showModalBottomSheet<TripConfirmation>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _TripConfirmSheet(
    title: title,
    regionIds: regionIds,
    regionNames: regionNames,
  ),
);

class _TripConfirmSheet extends StatefulWidget {
  const _TripConfirmSheet({
    required this.title,
    required this.regionIds,
    required this.regionNames,
  });

  final String title;
  final List<String> regionIds;
  final Map<String, String> regionNames;

  @override
  State<_TripConfirmSheet> createState() => _TripConfirmSheetState();
}

class _TripConfirmSheetState extends State<_TripConfirmSheet> {
  late final _title = TextEditingController(text: widget.title);
  late final _all = [...widget.regionIds];
  late final _selected = {...widget.regionIds};

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: '제목'),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            for (final id in _all)
              FilterChip(
                label: Text(widget.regionNames[id] ?? id),
                selected: _selected.contains(id),
                onSelected: (on) => setState(
                  () => on ? _selected.add(id) : _selected.remove(id),
                ),
              ),
            ActionChip(
              avatar: const Icon(Icons.add),
              label: const Text('조각 추가'),
              onPressed: () async {
                final picked = await pickRegions(context, initial: _selected);
                if (picked == null) return;
                setState(() {
                  _all.addAll(picked.where((id) => !_all.contains(id)));
                  _selected
                    ..clear()
                    ..addAll(picked);
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(
                  context,
                  TripConfirmation(_title.text.trim(), [
                    for (final id in _all)
                      if (_selected.contains(id)) id,
                  ]),
                ),
          child: const Text('지도에 채우기'),
        ),
      ],
    ),
  );
}
