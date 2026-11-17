import '../../core/result/result.dart';
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
