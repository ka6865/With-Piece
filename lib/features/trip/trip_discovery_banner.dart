import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/result/result.dart';
import '../scan/scan_providers.dart';

// 전국 지도 위에서 새 여행 후보나 사진 권한 안내를 보여준다.
// 그 밖의 오류(오프라인 등)에서는 지도를 가리지 않도록 아무것도 보이지 않는다
class TripDiscoveryBanner extends ConsumerWidget {
  const TripDiscoveryBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidates = ref.watch(tripCandidatesProvider);
    // Riverpod 3는 실패한 provider를 자동으로 다시 시도하고, 그동안 상태는
    // 오류를 품은 로딩이다. 상태 종류가 아니라 품은 값과 오류로 판단한다
    final found = candidates.value;
    if (found != null && found.isNotEmpty) {
      return _Banner(
        message: '함께 간 여행 ${found.length}개를 찾았어요',
        action: '보기',
        onPressed: () => context.push('/trips/candidates'),
      );
    }
    if (candidates.error == AppError.photoPermission) {
      return const _Banner(
        message: '사진 전체 접근을 허용하면 함께 간 곳을 찾아드려요',
        action: '설정 열기',
        onPressed: PhotoManager.openSetting,
      );
    }
    if (found == null) return const SizedBox.shrink();
    return Row(
      children: [
        Expanded(
          child: _Banner(
            message: '비교할 기록을 골라 함께 간 곳을 찾아보세요',
            action: '기록 선택',
            onPressed: () => context.push('/settings/photo-sharing'),
          ),
        ),
        IconButton(
          tooltip: '함께 간 기록 새로 확인',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref
            ..invalidate(matchedDaysProvider)
            ..invalidate(tripCandidatesProvider),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.action,
    required this.onPressed,
  });

  final String message;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Expanded(child: Text(message)),
          TextButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    ),
  );
}
