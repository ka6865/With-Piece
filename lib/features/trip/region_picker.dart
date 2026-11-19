import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../map_data/map_asset_loader.dart';

// 시도를 고른 뒤 그 시도의 조각을 여러 개 고른다. 지역은 코드로만 다룬다
Future<Set<String>?> pickRegions(
  BuildContext context, {
  required Set<String> initial,
}) => showDialog<Set<String>>(
  context: context,
  builder: (_) => _RegionPicker(initial: initial),
);

// 조각 하나를 고른다. 누르는 즉시 닫힌다
Future<String?> pickRegion(BuildContext context, {required String title}) =>
    showDialog<Set<String>>(
      context: context,
      builder: (_) => _RegionPicker(initial: const {}, single: title),
    ).then((picked) => picked?.firstOrNull);

class _RegionPicker extends ConsumerStatefulWidget {
  const _RegionPicker({required this.initial, this.single});

  final Set<String> initial;
  // 하나만 고를 때의 제목. 있으면 체크 대신 누르는 즉시 돌려준다
  final String? single;

  @override
  ConsumerState<_RegionPicker> createState() => _RegionPickerState();
}

class _RegionPickerState extends ConsumerState<_RegionPicker> {
  late final _selected = {...widget.initial};
  String? _provinceId;

  @override
  Widget build(BuildContext context) {
    final provinces = ref.watch(provinceMapAssetProvider).value;
    final regions = ref.watch(regionMapAssetProvider).value;
    if (provinces == null || regions == null) {
      return const AlertDialog(content: LinearProgressIndicator());
    }
    final provinceId = _provinceId ?? provinces.features.first.id;
    return AlertDialog(
      title: Text(widget.single ?? '조각 추가'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButton<String>(
              value: provinceId,
              isExpanded: true,
              items: [
                for (final p in provinces.features)
                  DropdownMenuItem(value: p.id, child: Text(p.name)),
              ],
              onChanged: (id) => setState(() => _provinceId = id),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final r in regions.features.where(
                    (f) => f.parentId == provinceId,
                  ))
                    if (widget.single != null)
                      ListTile(
                        title: Text(r.name),
                        onTap: () => Navigator.pop(context, {r.id}),
                      )
                    else
                      CheckboxListTile(
                        title: Text(r.name),
                        value: _selected.contains(r.id),
                        onChanged: (on) => setState(
                          () => on!
                              ? _selected.add(r.id)
                              : _selected.remove(r.id),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        if (widget.single == null)
          FilledButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: const Text('완료'),
          ),
      ],
    );
  }
}
