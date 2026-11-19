import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import 'couple_days.dart';

// 두 사람이 연결된 뒤 처음 홈에 들어올 때 한 번, 오늘에서 사귄 날로 시간을 되감고
// D+N까지 다시 세어 올라온다(커플 디자인 4.6). 날짜를 고른 사람도 상대도 같은
// 경로(홈 첫 진입)로 본다. 본 기록은 기기에 사용자·커플 키로 남긴다
class RewindGate extends ConsumerStatefulWidget {
  const RewindGate({
    super.key,
    required this.userId,
    required this.coupleId,
    required this.startedOn,
  });

  final String userId;
  final String coupleId;
  final DateTime startedOn;

  static String seenKey(String userId, String coupleId) =>
      'rewind_seen:$userId:$coupleId';

  @override
  ConsumerState<RewindGate> createState() => _RewindGateState();
}

class _RewindGateState extends ConsumerState<RewindGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (!mounted) return;
    final prefs = ref.read(sharedPreferencesProvider);
    final key = RewindGate.seenKey(widget.userId, widget.coupleId);
    if (prefs.getBool(key) ?? false) return;
    // 보여 주기 전에 남겨 앱이 중간에 꺼져도 다시 반복하지 않는다
    await prefs.setBool(key, true);
    if (!mounted || MediaQuery.disableAnimationsOf(context)) return;
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => RewindPage(startedOn: widget.startedOn),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class RewindPage extends StatefulWidget {
  const RewindPage({super.key, required this.startedOn, this.today});

  final DateTime startedOn;
  // 테스트가 오늘을 고정할 수 있게 둔다
  final DateTime? today;

  // 되감기·머무름·세어 올라오기의 시간 비율
  static const rewindEnd = 0.55;
  static const holdEnd = 0.75;

  @override
  State<RewindPage> createState() => _RewindPageState();
}

class _RewindPageState extends State<RewindPage>
    with SingleTickerProviderStateMixin {
  // 사귄 날이 아무리 멀어도 하루씩 넘기지 않고 같은 길이 안에서 가속해 되감는다
  late final _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _close();
        })
        ..forward();

  late final DateTime _today = widget.today ?? DateTime.now();

  bool _closed = false;

  void _close() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = DateTime(
      widget.startedOn.year,
      widget.startedOn.month,
      widget.startedOn.day,
    );
    final total = daysTogether(start, _today);
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: SafeArea(
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(onPressed: _close, child: const Text('건너뛰기')),
              ),
              Center(
                child: Semantics(
                  label: '${formatStartedOn(start)}부터 함께한 지 $total일째',
                  child: ExcludeSemantics(
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) =>
                          _frame(theme, start, total, _controller.value),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _frame(ThemeData theme, DateTime start, int total, double t) {
    final big = theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      color: theme.colorScheme.primary,
    );
    final caption = theme.textTheme.titleMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final String value;
    final String label;
    if (t < RewindPage.rewindEnd) {
      // 끝으로 갈수록 느려져 사귄 날에 부드럽게 닿는다
      final p = Curves.easeOutCubic.transform(t / RewindPage.rewindEnd);
      final back = ((total - 1) * p).round();
      value = formatStartedOn(
        DateTime(_today.year, _today.month, _today.day - back),
      );
      label = '시간을 거슬러';
    } else if (t < RewindPage.holdEnd) {
      value = formatStartedOn(start);
      label = '우리가 시작한 날';
    } else {
      final p = Curves.easeInCubic.transform(
        (t - RewindPage.holdEnd) / (1 - RewindPage.holdEnd),
      );
      value = 'D+${math.max(1, (total * p).round())}';
      label = '그리고 오늘까지';
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 작은 화면·큰 글씨에서 날짜가 넘치지 않게 줄인다
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: big),
          ),
        ),
        const SizedBox(height: 12),
        Text(label, style: caption),
      ],
    );
  }
}
