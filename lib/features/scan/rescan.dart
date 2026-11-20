import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../data/repositories/repository_providers.dart';
import '../../core/supabase/supabase_providers.dart';
import '../auth/account_state.dart';
import 'scan_providers.dart';
import 'scanner.dart';

Future<Result<void>> rescan(Scanner scanner, void Function() onSuccess) async {
  try {
    final result = await scanner.scan(full: true);
    if (result case Err(:final error)) return Err(error);
    onSuccess();
    return const Ok(null);
  } catch (_) {
    return const Err(AppError.unknown);
  }
}

// 설정(커플이 아닐 때)과 최신화 탭이 함께 쓰는 사진첩 전체 다시 읽기
Future<Result<void>> rescanLibrary(WidgetRef ref) async {
  try {
    final userId = ref.read(sessionUserIdProvider);
    if (userId == null) return const Err(AppError.validation);
    DateTime? deletionDate;
    try {
      deletionDate = await ref.read(myDeletionDateProvider(userId).future);
    } catch (_) {}
    if (deletionDate != null) return const Err(AppError.validation);
    final store = await ref.read(scanStoreProvider(userId).future);
    if (store.isDeletionPending) return const Err(AppError.validation);
    return await rescan(
      Scanner(
        ref.read(photoLibraryRepositoryProvider),
        await ref.read(regionLocatorProvider.future),
        store,
      ),
      () => ref.invalidate(scanSnapshotProvider(userId)),
    );
  } catch (_) {
    return const Err(AppError.unknown);
  }
}

String rescanFailureMessage(AppError error) => error == AppError.photoPermission
    ? '사진 전체 접근을 허용한 뒤 다시 시도해 주세요'
    : '다시 스캔하지 못했어요. 잠시 뒤 다시 시도해 주세요';
