import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/auth_repository.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';

class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.identityCount = 1});

  final int identityCount;
  int signOutCalls = 0;

  @override
  OAuthProvider? get lastProvider => null;

  @override
  Future<void> rememberProvider(OAuthProvider provider) async {}

  @override
  Future<Result<void>> signIn(OAuthProvider provider) async => const Ok(null);

  @override
  Future<Result<void>> link(OAuthProvider provider) async => const Ok(null);

  @override
  Future<Result<List<UserIdentity>>> identities() async => Ok([
    for (var i = 0; i < identityCount; i++)
      UserIdentity(
        id: '$i',
        userId: 'u',
        identityData: const {},
        identityId: 'i$i',
        provider: i == 0 ? 'kakao' : 'apple',
        createdAt: null,
        lastSignInAt: null,
        updatedAt: null,
      ),
  ]);

  @override
  Future<Result<void>> unlink(UserIdentity identity) async => const Ok(null);

  @override
  Future<Result<void>> signOut() async {
    signOutCalls++;
    return const Ok(null);
  }
}

class FakeCoupleRepository implements CoupleRepository {
  final joinedCodes = <String>[];
  final startedOnCalls = <DateTime>[];
  int devSoloJoins = 0;

  @override
  Future<Result<JoinOutcome>> joinDevSolo() async {
    devSoloJoins++;
    return const Ok(JoinOutcome.joined);
  }

  @override
  Future<Result<Invite>> createInvite() async =>
      Ok(Invite(code: 'MYCODE2345', expiresAt: DateTime(2026, 12, 1)));

  @override
  Future<Result<Invite?>> myInvite() async => const Ok(null);

  @override
  Future<Result<JoinOutcome>> join(String code) async {
    joinedCodes.add(code);
    return const Ok(JoinOutcome.invalidCode);
  }

  @override
  Future<Result<void>> setStartedOn(DateTime date) async {
    startedOnCalls.add(DateTime(date.year, date.month, date.day));
    return const Ok(null);
  }

  final homeRegions = <String>[];

  @override
  Future<Result<void>> setHomeRegion(String regionId) async {
    homeRegions.add(regionId);
    return const Ok(null);
  }

  int archives = 0;

  @override
  Future<Result<void>> archive() async {
    archives++;
    return const Ok(null);
  }

  @override
  Future<Result<Couple?>> current() async => const Ok(null);

  @override
  Future<Result<List<ArchivedCouple>>> archived() async => const Ok([]);
}
