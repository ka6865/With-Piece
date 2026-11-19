import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../data/repositories/comment_repository.dart';
import '../../data/repositories/repository_providers.dart';
import '../auth/auth_state.dart';

// 방명록과 사진 댓글(설계 6.2). 상대 댓글은 Realtime 알림으로 다시 읽고, 푸시 전에는
// 앨범의 "새 댓글" 표시로만 알린다

// 사용자 id를 키에 넣어 계정이 바뀌면 이전 계정으로 읽은 목록을 잇지 않는다
typedef CommentTarget = ({CommentKind kind, String id, String userId});

final commentsProvider = FutureProvider.autoDispose
    .family<List<Comment>, CommentTarget>((ref, target) async {
      if (ref.watch(sessionUserIdProvider) != target.userId) return const [];
      final repository = ref.watch(commentRepositoryProvider);
      return (await repository.list(target.kind, target.id)).valueOrThrow;
    });

// 여행별로 상대가 남긴 최신 댓글 시각
final partnerCommentTimesProvider = FutureProvider.autoDispose
    .family<Map<String, DateTime>, CoupleScope>((ref, scope) async {
      if (ref.watch(currentCoupleScopeProvider) != scope) return const {};
      final repository = ref.watch(commentRepositoryProvider);
      return (await repository.partnerLatestByTrip(
        scope.coupleId,
      )).valueOrThrow;
    });

// 여행별로 마지막으로 본 상대 댓글 시각. 기기에만 둔다(사용자·여행 키)
class CommentSeen extends Notifier<int> {
  @override
  int build() => 0;

  static String _key(String userId, String tripId) =>
      'comment_seen:$userId:$tripId';

  DateTime? seenAt(String userId, String tripId) => switch (ref
      .read(sharedPreferencesProvider)
      .getString(_key(userId, tripId))) {
    final String at => DateTime.parse(at),
    _ => null,
  };

  Future<void> markSeen(String userId, String tripId, DateTime at) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_key(userId, tripId), at.toIso8601String());
    state++;
  }
}

final commentSeenProvider = NotifierProvider<CommentSeen, int>(CommentSeen.new);

// 상대가 남긴 댓글을 아직 이 기기에서 보지 않은 여행인지
bool hasUnseenComment(WidgetRef ref, CoupleScope? scope, String tripId) {
  if (scope == null) return false;
  ref.watch(commentSeenProvider);
  final latest = ref.watch(partnerCommentTimesProvider(scope)).value?[tripId];
  if (latest == null) return false;
  final seen = ref
      .read(commentSeenProvider.notifier)
      .seenAt(scope.userId, tripId);
  return seen == null || latest.isAfter(seen);
}

class CommentSection extends ConsumerStatefulWidget {
  const CommentSection({
    super.key,
    required this.kind,
    required this.targetId,
    required this.coupleId,
    this.tripId,
  });

  final CommentKind kind;
  final String targetId;
  // 대상이 속한 커플. 지금 활성 커플이 아니면(지난 기록) 읽기만 한다
  final String? coupleId;
  // 방명록이면 열었을 때 그 여행의 새 댓글 표시를 지운다
  final String? tripId;

  @override
  ConsumerState<CommentSection> createState() => _CommentSectionState();
}

class _CommentSectionState extends ConsumerState<CommentSection> {
  final _input = TextEditingController();
  bool _sending = false;
  // 창을 연 계정. 바텀시트처럼 계정이 바뀌어도 남는 화면에서 이전 글을 숨긴다
  late final String? _openedBy = ref.read(sessionUserIdProvider);

  CommentTarget get _target =>
      (kind: widget.kind, id: widget.targetId, userId: _openedBy ?? '');

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _run(Future<Result<void>> action) async {
    final result = await action;
    if (!mounted) return;
    if (result is Err) _toast('저장하지 못했어요');
    ref.invalidate(commentsProvider(_target));
  }

  Future<void> _send(String coupleId) async {
    final content = _input.text.trim();
    if (content.isEmpty || _sending) return;
    setState(() => _sending = true);
    final result = await ref
        .read(commentRepositoryProvider)
        .add(
          widget.kind,
          targetId: widget.targetId,
          coupleId: coupleId,
          content: content,
        );
    if (!mounted) return;
    setState(() => _sending = false);
    if (result is Err) {
      _toast('남기지 못했어요. 글은 그대로예요');
      return;
    }
    _input.clear();
    ref.invalidate(commentsProvider(_target));
  }

  Future<void> _edit(Comment comment) async {
    final content = await showDialog<String>(
      context: context,
      builder: (context) => _EditDialog(initial: comment.content),
    );
    if (content == null || content.isEmpty || content == comment.content) {
      return;
    }
    await _run(
      ref
          .read(commentRepositoryProvider)
          .edit(widget.kind, comment.id, content),
    );
  }

  Future<void> _menu(Comment comment) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('고치기'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('지우기'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'edit':
        await _edit(comment);
      case 'delete':
        await _run(
          ref.read(commentRepositoryProvider).delete(widget.kind, comment.id),
        );
    }
  }

  // 열어 본 여행의 상대 최신 댓글 시각을 본 것으로 남긴다. 본 값과 같아지면 다시 남기지 않는다
  void _markSeen() {
    final tripId = widget.tripId;
    final scope = ref.watch(currentCoupleScopeProvider);
    if (tripId == null || scope == null) return;
    final latest = ref.watch(partnerCommentTimesProvider(scope)).value?[tripId];
    if (latest == null) return;
    ref.watch(commentSeenProvider);
    final seen = ref
        .read(commentSeenProvider.notifier)
        .seenAt(scope.userId, tripId);
    if (seen != null && !latest.isAfter(seen)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(commentSeenProvider.notifier)
            .markSeen(scope.userId, tripId, latest);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(sessionUserIdProvider);
    if (me == null || me != _openedBy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('계정이 바뀌어 글을 닫았어요'),
      );
    }
    _markSeen();
    final theme = Theme.of(context);
    final couple = ref.watch(scopedCurrentCoupleProvider).value;
    final coupleId = widget.coupleId;
    final writable = coupleId != null && couple?.id == coupleId;
    final comments = ref.watch(commentsProvider(_target));
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final rows = comments.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              comments.hasError ? '글을 불러오지 못했어요' : '글을 불러오는 중이에요',
              style: muted,
            ),
          )
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('아직 남긴 글이 없어요', style: muted),
          )
        else
          for (final comment in rows)
            InkWell(
              onLongPress: writable && comment.authorId == me
                  ? () => _menu(comment)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        comment.authorId == me
                            ? '나'
                            // 지난 커플의 글에 지금 상대 이름을 붙이지 않는다
                            : comment.authorId == couple?.partnerId
                            ? couple?.partnerName ?? '상대'
                            : '상대',
                        _time(comment.createdAt),
                        if (comment.updatedAt != null) '수정됨',
                      ].join(' · '),
                      style: muted,
                    ),
                    const SizedBox(height: 2),
                    Text(comment.content, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
        if (writable)
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: 200,
                  maxLines: null,
                  decoration: InputDecoration(
                    hintText: widget.kind == CommentKind.trip
                        ? '이 여행에 한마디 남겨요'
                        : '이 사진에 한마디 남겨요',
                    counterText: '',
                  ),
                ),
              ),
              IconButton(
                tooltip: '남기기',
                icon: const Icon(Icons.send),
                onPressed: _sending ? null : () => _send(coupleId),
              ),
            ],
          ),
      ],
    );
  }

  static String _time(DateTime at) {
    final local = at.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}.${local.day} ${local.hour}:$minute';
  }
}

// 컨트롤러 수명을 대화상자에 맞춰 닫히는 애니메이션 중에도 쓸 수 있게 한다
class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.initial});

  final String initial;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('글 고치기'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 200,
      maxLines: null,
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('저장'),
      ),
    ],
  );
}
