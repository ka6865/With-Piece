import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final sessionProvider = StreamProvider<Session?>(
  (ref) => ref
      .watch(supabaseClientProvider)
      .auth
      .onAuthStateChange
      .map((state) => state.session),
);

final sessionUserIdProvider = Provider<String?>((ref) {
  final session = ref.watch(sessionProvider);
  if (session.isLoading || session.hasError) return null;
  return session.value?.user.id;
});
