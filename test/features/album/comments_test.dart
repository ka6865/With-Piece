import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:woori_piece/core/result/result.dart';
import 'package:woori_piece/core/supabase/supabase_providers.dart';
import 'package:woori_piece/data/repositories/comment_repository.dart';
import 'package:woori_piece/data/repositories/couple_repository.dart';
import 'package:woori_piece/data/repositories/repository_providers.dart';
import 'package:woori_piece/features/album/comments.dart';
import 'package:woori_piece/features/auth/auth_state.dart';

class _FakeComments extends CommentRepository {
  _FakeComments(this.rows)
    : super(
        SupabaseClient(
          'http://127.0.0.1:1',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final List<Comment> rows;
  final added = <String>[];

  @override
  Future<Result<List<Comment>>> list(CommentKind kind, String targetId) async =>
      Ok(List.of(rows));

  @override
  Future<Result<void>> add(
    CommentKind kind, {
    required String targetId,
    required String coupleId,
    required String content,
  }) async {
    added.add(content);
    return const Ok(null);
  }
}

final _rows = [
  Comment(
    id: 'g1',
    authorId: 'me',
    content: '또 가자',
    createdAt: DateTime.utc(2026, 10, 4, 3),
  ),
  Comment(
    id: 'g2',
    authorId: 'p',
    content: '다음엔 겨울에',
    createdAt: DateTime.utc(2026, 10, 4, 4),
    updatedAt: DateTime.utc(2026, 10, 4, 5),
  ),
];

Future<_FakeComments> _pump(
  WidgetTester tester, {
  String coupleId = 'c1',
  Map<String, DateTime> partnerTimes = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = _FakeComments(_rows);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionUserIdProvider.overrideWithValue('me'),
        sharedPreferencesProvider.overrideWithValue(prefs),
        commentRepositoryProvider.overrideWithValue(repo),
        currentCoupleProvider.overrideWith(
          (ref) async =>
              const Couple(id: 'c1', partnerId: 'p', partnerName: '준호'),
        ),
        partnerCommentTimesProvider.overrideWith(
          (ref, scope) async => partnerTimes,
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              CommentSection(
                kind: CommentKind.trip,
                targetId: 't1',
                coupleId: coupleId,
                tripId: 't1',
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('작성자 이름과 수정됨을 보여 주고 글을 남긴다', (tester) async {
    final repo = await _pump(tester);
    expect(find.text('또 가자'), findsOneWidget);
    expect(find.textContaining('나 · '), findsOneWidget);
    expect(find.textContaining('준호 · '), findsOneWidget);
    expect(find.textContaining('수정됨'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  좋았어  ');
    await tester.tap(find.byTooltip('남기기'));
    await tester.pumpAndSettle();
    expect(repo.added, ['좋았어']);
    expect(find.widgetWithText(TextField, '좋았어'), findsNothing);
  });

  testWidgets('내 글만 길게 눌러 고치거나 지울 수 있다', (tester) async {
    await _pump(tester);
    await tester.longPress(find.text('다음엔 겨울에'));
    await tester.pumpAndSettle();
    expect(find.text('고치기'), findsNothing);
    await tester.longPress(find.text('또 가자'));
    await tester.pumpAndSettle();
    expect(find.text('고치기'), findsOneWidget);
    expect(find.text('지우기'), findsOneWidget);
  });

  testWidgets('지난 커플의 글은 읽기만 한다', (tester) async {
    await _pump(tester, coupleId: 'c-old');
    expect(find.text('또 가자'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.longPress(find.text('또 가자'));
    await tester.pumpAndSettle();
    expect(find.text('고치기'), findsNothing);
  });

  testWidgets('방명록을 열면 그 여행의 새 글 표시를 지운다', (tester) async {
    final at = DateTime.utc(2026, 10, 4, 4);
    await _pump(tester, partnerTimes: {'t1': at});
    final container = ProviderScope.containerOf(
      tester.element(find.byType(CommentSection)),
    );
    expect(container.read(commentSeenProvider.notifier).seenAt('me', 't1'), at);
  });
}
