import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/couple_repository.dart';
import '../../data/repositories/photo_repository.dart';
import '../../data/repositories/trip_repository.dart';
import '../../map_data/map_asset_loader.dart';
import '../album/album_providers.dart';
import '../album/photo_grid.dart';
import '../auth/auth_state.dart';
import '../map/view/mini_puzzle_map.dart';
import '../scan/progress.dart';
import '../scan/scan_providers.dart';
import '../trip/trip_candidates_page.dart';
import '../trip/trip_discovery_banner.dart';
import 'couple_days.dart';
import 'rewind_page.dart';

// 커플 상태의 첫 화면. 두 사람과 함께한 날, 채운 조각, 최근 여행을 모아 본다
// (커플 디자인 4.2)
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(currentCoupleScopeProvider);
    final couple = ref.watch(scopedCurrentCoupleProvider).value;
    final trips = scope == null
        ? null
        : ref.watch(scopedTripsProvider(scope)).value;
    final home = scope == null
        ? null
        : ref.watch(scopedHomeRegionIdsProvider(scope)).value;
    final photos = scope == null
        ? null
        : ref.watch(scopedCouplePhotosProvider(scope)).value;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          children: [
            if (couple != null) _Header(couple: couple),
            if ((scope, couple?.startedOn) case (
              final scope?,
              final startedOn?,
            ))
              RewindGate(
                key: ValueKey(scope),
                userId: scope.userId,
                coupleId: scope.coupleId,
                startedOn: startedOn,
              ),
            if (scope != null)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                  child: TripDiscoveryBanner(),
                ),
              ),
            _PiecesCard(trips: trips ?? const [], home: home ?? const {}),
            _RecentTripCard(
              trips: trips,
              photos: photos ?? const [],
              scopeKey: scope,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.couple});

  final Couple couple;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final startedOn = couple.startedOn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: startedOn == null
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'D+${daysTogether(startedOn, DateTime.now())}',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      Text(
                        '${formatStartedOn(startedOn)}부터 함께',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          _Avatar(initialOf(couple.myName, '나')),
          // 두 아바타를 살짝 겹쳐 한 쌍으로 보이게 한다
          Transform.translate(
            offset: const Offset(-10, 0),
            child: _Avatar(initialOf(couple.partnerName, '너')),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.initial);

  final String initial;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 2),
      ),
      child: CircleAvatar(
        radius: 22,
        backgroundColor: scheme.secondaryContainer,
        foregroundColor: scheme.onSecondaryContainer,
        child: Text(
          initial,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _PiecesCard extends ConsumerWidget {
  const _PiecesCard({required this.trips, required this.home});

  final List<Trip> trips;
  final Set<String> home;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final regions = ref.watch(regionMapAssetProvider).value;
    final filled = filledRegionIds(trips, home);
    final total = regions?.features.length;
    return _HomeCard(
      onTap: () => context.go('/map'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('우리의 조각', style: theme.textTheme.titleMedium),
              ),
              if (total != null)
                Text(
                  '${filled.length} / $total',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: regions == null
                ? const SizedBox.shrink()
                : MiniPuzzleMap(
                    asset: regions,
                    visitedRegionIds: filled,
                    homeRegionIds: home,
                  ),
          ),
          if (total != null) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: filled.length / total,
                minHeight: 8,
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.secondaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentTripCard extends ConsumerWidget {
  const _RecentTripCard({
    required this.trips,
    required this.photos,
    required this.scopeKey,
  });

  final List<Trip>? trips;
  final List<PhotoRecord> photos;
  final Object? scopeKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rows = trips;
    if (rows == null) return const SizedBox.shrink();
    final confirmed = [...rows.where((t) => t.status == TripStatus.confirmed)]
      ..sort((a, b) => b.range.start.compareTo(a.range.start));
    final latest = confirmed.firstOrNull;
    final thumbs = latest == null
        ? const <PhotoRecord>[]
        : photos.where((p) => p.tripId == latest.id).take(3).toList();
    return _HomeCard(
      onTap: latest == null ? null : () => context.push('/trips/${latest.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('최근 여행', style: theme.textTheme.titleMedium),
              ),
              if (latest != null)
                TextButton(
                  onPressed: () => context.go('/album'),
                  child: const Text('전체'),
                ),
            ],
          ),
          if (latest == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '첫 여행을 여기 담아볼까요?',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else ...[
            if (thumbs.isNotEmpty)
              FutureBuilder<Map<String, String>>(
                key: ValueKey(scopeKey),
                future: ref.watch(signedUrlCacheProvider).urls([
                  for (final p in thumbs) p.thumbPath,
                ]),
                builder: (context, urls) => Row(
                  spacing: 8,
                  children: [
                    for (final p in thumbs)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox.square(
                          dimension: 72,
                          child: RemoteImage(url: urls.data?[p.thumbPath]),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(latest.title, style: theme.textTheme.bodyLarge),
            Text(
              formatRange(latest.range),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  const _HomeCard({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}
