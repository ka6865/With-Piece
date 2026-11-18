import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/data/repositories/comment_repository.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/trip_repository.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';

import 'support.dart';

Future<String> _couple(SupabaseClient a, SupabaseClient b) async {
  final invite = (await CoupleRepository(a).createInvite()).valueOrThrow;
  (await CoupleRepository(b).join(invite.code)).valueOrThrow;
  return (await CoupleRepository(a).current()).valueOrThrow!.id;
}

Future<void> main() async {
  final skip = await localStackSkipReason();

  test('방명록과 사진 댓글을 쓰고 고치고 지우며 상대가 읽는다', () async {
    final a = await signUpLocal();
    final b = await signUpLocal();
    addTearDown(a.dispose);
    addTearDown(b.dispose);
    final coupleId = await _couple(a, b);
    final tripId = (await TripRepository(a).confirm(
      title: '속초시',
      range: DateRange(DateTime(2026, 10, 3), DateTime(2026, 10, 3)),
      regionIds: ['32060'],
      source: TripSource.manual,
    )).valueOrThrow;
    final photoId =
        (await a
                .from('photos')
                .insert({
                  'couple_id': coupleId,
                  'trip_id': tripId,
                  'object_key': '$coupleId/$tripId/c.jpg',
                  'width': 1,
                  'height': 1,
                  'byte_size': 1,
                })
                .select('id')
                .single())['id']
            as String;
    final ca = CommentRepository(a);
    final cb = CommentRepository(b);

    (await ca.add(
      CommentKind.trip,
      targetId: tripId,
      coupleId: coupleId,
      content: '또 가자',
    )).valueOrThrow;
    (await cb.add(
      CommentKind.photo,
      targetId: photoId,
      coupleId: coupleId,
      content: '이 사진 좋다',
    )).valueOrThrow;

    final fromB = (await cb.list(CommentKind.trip, tripId)).valueOrThrow;
    expect(fromB.single.content, '또 가자');
    expect(fromB.single.authorId, a.auth.currentUser!.id);
    expect(fromB.single.updatedAt, isNull);

    (await ca.edit(CommentKind.trip, fromB.single.id, '또 가자!')).valueOrThrow;
    final edited = (await cb.list(CommentKind.trip, tripId)).valueOrThrow;
    expect(edited.single.content, '또 가자!');
    expect(edited.single.updatedAt, isNotNull);

    // 상대 글은 RLS로 걸러져 아무 행도 바뀌지 않는다
    await cb.edit(CommentKind.trip, fromB.single.id, '바꿈');
    expect(
      (await ca.list(CommentKind.trip, tripId)).valueOrThrow.single.content,
      '또 가자!',
    );

    // a가 보기에 상대(b)의 최신 댓글은 사진 댓글을 거쳐 그 여행에 묶인다
    final latest = (await ca.partnerLatestByTrip(
      coupleId,
      a.auth.currentUser!.id,
    )).valueOrThrow;
    expect(latest.keys, [tripId]);

    final photoComment = (await cb.list(
      CommentKind.photo,
      photoId,
    )).valueOrThrow.single;
    (await cb.delete(CommentKind.photo, photoComment.id)).valueOrThrow;
    expect((await ca.list(CommentKind.photo, photoId)).valueOrThrow, isEmpty);
  }, skip: skip);
}
