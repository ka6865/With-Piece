import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/result/result.dart';
import 'fetch_all.dart';

// 방명록(여행 댓글)과 사진 댓글. 두 테이블은 대상 칸만 다르다(설계 6.2)
enum CommentKind {
  trip('guestbook_entries', 'trip_id'),
  photo('photo_comments', 'photo_id');

  const CommentKind(this.table, this.targetColumn);

  final String table;
  final String targetColumn;
}

class Comment {
  const Comment({
    required this.id,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String authorId;
  final String content;
  final DateTime createdAt;
  // 고친 적이 있으면 "수정됨"을 표시한다
  final DateTime? updatedAt;
}

class CommentRepository {
  const CommentRepository(this._client);

  final SupabaseClient _client;

  Future<Result<List<Comment>>> list(CommentKind kind, String targetId) =>
      guard(() async {
        final query = _client
            .from(kind.table)
            .select('id, author_id, content, created_at, updated_at')
            .eq(kind.targetColumn, targetId)
            .order('created_at')
            .order('id');
        final rows = await fetchAll((from, to) => query.range(from, to));
        return [
          for (final row in rows)
            Comment(
              id: row['id'] as String,
              authorId: row['author_id'] as String,
              content: row['content'] as String,
              createdAt: DateTime.parse(row['created_at'] as String),
              updatedAt: switch (row['updated_at']) {
                final String at => DateTime.parse(at),
                _ => null,
              },
            ),
        ];
      });

  // 작성자·시각은 서버가 정한다. 쓰기는 활성 커플만 RLS로 허용된다(설계 9장)
  Future<Result<void>> add(
    CommentKind kind, {
    required String targetId,
    required String coupleId,
    required String content,
  }) => guard(
    () => _client.from(kind.table).insert({
      kind.targetColumn: targetId,
      'couple_id': coupleId,
      'content': content,
    }),
  );

  Future<Result<void>> edit(CommentKind kind, String id, String content) =>
      guard(
        () =>
            _client.from(kind.table).update({'content': content}).eq('id', id),
      );

  Future<Result<void>> delete(CommentKind kind, String id) =>
      guard(() => _client.from(kind.table).delete().eq('id', id));

  // 여행마다 상대가 남긴 가장 최근 댓글 시각. 앨범의 "새 댓글" 표시에 쓴다(설계 6.2)
  Future<Result<Map<String, DateTime>>> partnerLatestByTrip(String coupleId) =>
      guard(() async {
        final rows = await fetchAll((from, to) async {
          final rows = await _client
              .rpc('partner_latest_comments', params: {'p_couple_id': coupleId})
              .range(from, to);
          return List<Map<String, dynamic>>.from(rows as List);
        });
        return {
          for (final row in rows)
            row['trip_id'] as String: DateTime.parse(
              row['latest_at'] as String,
            ),
        };
      });
}
