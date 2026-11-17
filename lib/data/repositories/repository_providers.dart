import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase/supabase_providers.dart';
import 'account_repository.dart';
import 'auth_repository.dart';
import 'couple_repository.dart';
import 'photo_day_repository.dart';
import 'photo_library_repository.dart';
import 'trip_repository.dart';

// main에서 SharedPreferences.getInstance() 결과로 override한다
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('main에서 override해야 한다'),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(sharedPreferencesProvider),
  ),
);

final coupleRepositoryProvider = Provider<CoupleRepository>(
  (ref) => CoupleRepository(ref.watch(supabaseClientProvider)),
);

final tripRepositoryProvider = Provider<TripRepository>(
  (ref) => TripRepository(ref.watch(supabaseClientProvider)),
);

final photoDayRepositoryProvider = Provider<PhotoDayRepository>(
  (ref) => PhotoDayRepository(ref.watch(supabaseClientProvider)),
);

final photoLibraryRepositoryProvider = Provider<PhotoLibraryRepository>(
  (ref) => const PhotoLibraryRepository(),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(supabaseClientProvider)),
);
