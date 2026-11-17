import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../data/repositories/repository_providers.dart';
import '../../data/repositories/trip_repository.dart';
import '../auth/auth_state.dart';
import '../scan/scan_providers.dart';
import '../scan/trip_candidates.dart';
import 'photo_upload_page.dart';
import 'region_picker.dart';
import 'trip_candidates_page.dart';

// 사진이 없거나 한 사람만 찍은 여행을 직접 만든다(설계 5.5)
class ManualTripPage extends ConsumerStatefulWidget {
  const ManualTripPage({super.key, required this.regionId});

  final String regionId;

  @override
  ConsumerState<ManualTripPage> createState() => _ManualTripPageState();
}

class _ManualTripPageState extends ConsumerState<ManualTripPage> {
  late final _regions = [widget.regionId];
  late var _range = _today();
  bool _saving = false;

  static DateRange _today() {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return DateRange(day, day);
  }

  Future<void> _save(Map<String, String> names) async {
    setState(() => _saving = true);
    final result = await ref
        .read(tripRepositoryProvider)
        .confirm(
          title: candidateTitle(_regions, _range, names),
          range: _range,
          regionIds: _regions,
          source: TripSource.manual,
        );
    if (!mounted) return;
    setState(() => _saving = false);
    switch (result) {
      case Ok(value: final tripId):
        ref.invalidate(tripsProvider);
        final coupleId = ref.read(currentCoupleProvider).value?.id;
        final navigator = Navigator.of(context);
        if (coupleId != null) {
          await navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => PhotoUploadPage(
                query: TripPhotoQuery(
                  coupleId: coupleId,
                  tripId: tripId,
                  range: _range,
                  regionIds: _regions.toSet(),
                ),
              ),
            ),
          );
        }
        await navigator.maybePop();
      case Err():
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('저장하지 못했어요')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = ref.watch(regionNamesProvider).value ?? const {};
    return Scaffold(
      appBar: AppBar(title: const Text('여행 만들기')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('기간'),
            subtitle: Text(formatRange(_range)),
            trailing: const Icon(Icons.date_range),
            onTap: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(1950),
                lastDate: DateTime.now(),
                initialDateRange: DateTimeRange(
                  start: _range.start,
                  end: _range.end,
                ),
              );
              if (picked != null) {
                setState(() => _range = DateRange(picked.start, picked.end));
              }
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final id in _regions)
                InputChip(
                  label: Text(names[id] ?? id),
                  onDeleted: _regions.length < 2
                      ? null
                      : () => setState(() => _regions.remove(id)),
                ),
              ActionChip(
                avatar: const Icon(Icons.add),
                label: const Text('조각 추가'),
                onPressed: () async {
                  final picked = await pickRegions(
                    context,
                    initial: _regions.toSet(),
                  );
                  if (picked == null || picked.isEmpty) return;
                  setState(() {
                    _regions
                      ..removeWhere((id) => !picked.contains(id))
                      ..addAll(picked.where((id) => !_regions.contains(id)));
                  });
                },
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _saving ? null : () => _save(names),
            child: const Text('지도에 채우기'),
          ),
        ),
      ),
    );
  }
}
