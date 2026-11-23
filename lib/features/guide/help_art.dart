import 'package:flutter/material.dart';

// 도움말 카드의 그림. 이미지 파일 없이 도형과 아이콘으로 화면을 줄여 그리고, 손가락이
// 누르거나 벌리는 모습을 짧게 되풀이한다. 동작 줄이기를 켜면 멈춘 한 장면만 보여준다
enum HelpArt {
  together,
  piecesCard,
  discovery,
  provinceTap,
  pieceTap,
  pieceLongPress,
  mapPinch,
  tripList,
  gridPinch,
  photoLongPress,
}

class HelpArtView extends StatefulWidget {
  const HelpArtView({super.key, required this.art});

  static const size = Size(240, 170);
  static const period = Duration(milliseconds: 2600);
  // 동작 줄이기일 때 보여줄 장면. 동작이 끝난 뒤의 모습이다
  static const stillT = 0.8;

  final HelpArt art;

  @override
  State<HelpArtView> createState() => _HelpArtViewState();
}

class _HelpArtViewState extends State<HelpArtView>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: HelpArtView.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = HelpArtView.stillT;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.fromSize(
      size: HelpArtView.size,
      // 확대 장면이 틀 밖으로 나가지 않게 자른다
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => _draw(
            widget.art,
            _controller.value,
            Theme.of(context).colorScheme,
          ),
        ),
      ),
    ),
  );
}

// t가 a에서 b로 가는 동안 0에서 1로 오른다
double _seg(double t, double a, double b) =>
    ((t - a) / (b - a)).clamp(0.0, 1.0);

Widget _tile(
  ColorScheme s, {
  double w = 44,
  double h = 44,
  bool filled = false,
  IconData? icon,
  double radius = 8,
}) => Container(
  width: w,
  height: h,
  decoration: BoxDecoration(
    color: filled ? s.primary : s.surfaceContainerHighest,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: s.outlineVariant),
  ),
  child: icon == null
      ? null
      : Icon(icon, size: w * 0.5, color: filled ? s.onPrimary : s.outline),
);

// 손가락 자리. press는 누르는 순간의 크기 변화, hold는 길게 누르기 진행
Widget _finger(ColorScheme s, {double press = 0, double hold = 0}) => SizedBox(
  width: 40,
  height: 40,
  child: Stack(
    alignment: Alignment.center,
    children: [
      Transform.scale(
        scale: 1 - 0.25 * press,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.tertiary.withValues(alpha: 0.35 + 0.3 * press),
          ),
        ),
      ),
      if (hold > 0)
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            value: hold,
            strokeWidth: 3,
            color: s.tertiary,
          ),
        ),
      Icon(Icons.touch_app, size: 20, color: s.onTertiaryContainer),
    ],
  ),
);

// 한 번 누르는 모습. a~b 사이에 눌렀다 뗀다
double _tap(double t, double a, double b) {
  final p = _seg(t, a, b);
  return p == 0 || p == 1 ? 0 : 1 - (2 * p - 1).abs();
}

Widget _pieces(ColorScheme s, {Set<int> filled = const {}, double size = 34}) =>
    Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < 9; i++)
          _tile(
            s,
            w: size,
            h: size,
            filled: filled.contains(i),
            icon: Icons.extension,
            radius: 6,
          ),
      ],
    );

Widget _label(ColorScheme s, String text, {bool strong = false}) => Text(
  text,
  style: TextStyle(
    fontSize: 12,
    fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
    color: strong ? s.primary : s.onSurfaceVariant,
  ),
);

Widget _draw(HelpArt art, double t, ColorScheme s) => switch (art) {
  HelpArt.together => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'D+100',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w800,
            color: s.primary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(radius: 16, child: _label(s, '나')),
            Transform.translate(
              offset: const Offset(-8, 0),
              child: CircleAvatar(radius: 16, child: _label(s, '너')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _label(s, '채운 조각 ${t < 0.5 ? 12 : 13} / 229', strong: t >= 0.5),
      ],
    ),
  ),
  HelpArt.piecesCard => Stack(
    children: [
      Positioned(
        left: 8,
        top: 20,
        child: Container(
          width: 130,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: s.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label(s, '우리의 조각', strong: true),
              const SizedBox(height: 6),
              _pieces(s, filled: {0, 4, 5}, size: 32),
            ],
          ),
        ),
      ),
      Positioned(
        left: 150,
        top: 70,
        child: Icon(Icons.arrow_forward, color: s.outline),
      ),
      Positioned(
        left: 182,
        top: 60,
        child: Icon(
          Icons.map,
          size: 46,
          color: t > 0.5 ? s.primary : s.outlineVariant,
        ),
      ),
      Positioned(
        left: 60,
        top: 80,
        child: _finger(s, press: _tap(t, 0.2, 0.45)),
      ),
    ],
  ),
  HelpArt.discovery => Stack(
    children: [
      Positioned(
        left: 20,
        top: 20,
        child: Container(
          width: 200,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: s.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: s.primary),
              const SizedBox(width: 8),
              _label(s, '새 여행 후보 1개', strong: true),
            ],
          ),
        ),
      ),
      Positioned(
        left: 98,
        top: 92,
        child: Icon(
          Icons.extension,
          size: 56,
          color: Color.lerp(s.outlineVariant, s.primary, _seg(t, 0.5, 0.7)),
        ),
      ),
      Positioned(
        left: 150,
        top: 22,
        child: _finger(s, press: _tap(t, 0.2, 0.45)),
      ),
    ],
  ),
  HelpArt.provinceTap => Stack(
    alignment: Alignment.center,
    children: [
      Opacity(
        opacity: 1 - _seg(t, 0.45, 0.6),
        child: _tile(s, w: 120, h: 120, icon: Icons.map, radius: 28),
      ),
      Opacity(
        opacity: _seg(t, 0.5, 0.65),
        child: SizedBox(width: 120, child: _pieces(s, size: 36)),
      ),
      Positioned(
        left: 120,
        top: 70,
        child: _finger(s, press: _tap(t, 0.2, 0.45)),
      ),
    ],
  ),
  HelpArt.pieceTap => Stack(
    children: [
      Positioned(
        left: 30,
        top: 20,
        child: Column(
          children: [
            _tile(s, w: 70, h: 70, filled: true, icon: Icons.photo),
            const SizedBox(height: 8),
            _label(s, '사진 보기', strong: t < 0.5),
          ],
        ),
      ),
      Positioned(
        left: 140,
        top: 20,
        child: Column(
          children: [
            _tile(s, w: 70, h: 70, icon: Icons.add),
            const SizedBox(height: 8),
            _label(s, '여행 만들기', strong: t >= 0.5),
          ],
        ),
      ),
      Positioned(
        left: t < 0.5 ? 45 : 155,
        top: 35,
        child: _finger(
          s,
          press: t < 0.5 ? _tap(t, 0.1, 0.35) : _tap(t, 0.6, 0.85),
        ),
      ),
    ],
  ),
  HelpArt.pieceLongPress => Stack(
    alignment: Alignment.center,
    children: [
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tile(
            s,
            w: 90,
            h: 90,
            filled: true,
            icon: t < 0.6 ? Icons.home : Icons.flight,
          ),
          const SizedBox(height: 10),
          _label(s, t < 0.6 ? '생활권' : '여행지', strong: true),
        ],
      ),
      Positioned(
        left: 120,
        top: 50,
        child: _finger(s, hold: t < 0.6 ? _seg(t, 0.15, 0.6) : 0),
      ),
    ],
  ),
  HelpArt.mapPinch => _pinch(
    s,
    t,
    Transform.scale(
      scale: 1 + 0.45 * _pinchAmount(t),
      child: SizedBox(
        width: 120,
        child: _pieces(s, filled: {1, 3, 4}, size: 36),
      ),
    ),
  ),
  HelpArt.tripList => Center(
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final name in ['강릉', '부산', '제주', '전주'])
          Container(
            width: 100,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: s.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                _tile(
                  s,
                  w: 34,
                  h: 34,
                  filled: true,
                  icon: Icons.photo,
                  radius: 6,
                ),
                const SizedBox(width: 6),
                _label(s, name, strong: true),
              ],
            ),
          ),
      ],
    ),
  ),
  HelpArt.gridPinch => _pinch(s, t, () {
    // 손가락을 벌릴수록 칸이 4 → 3 → 2로 줄어 사진이 커진다
    final p = _pinchAmount(t);
    final columns = p < 0.33 ? 4 : (p < 0.66 ? 3 : 2);
    final cell = (150 - 4 * (columns - 1)) / columns;
    return SizedBox(
      width: 150,
      height: 150,
      child: ClipRect(
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < 16; i++)
              _tile(
                s,
                w: cell,
                h: cell,
                filled: i.isEven,
                icon: Icons.photo,
                radius: 4,
              ),
          ],
        ),
      ),
    );
  }()),
  HelpArt.photoLongPress => Stack(
    alignment: Alignment.center,
    children: [
      SizedBox(
        // 3칸 2줄
        width: 52 * 3 + 4 * 2,
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < 6; i++)
              _tile(
                s,
                w: 52,
                h: 52,
                filled: i == 1,
                icon: Icons.photo,
                radius: 4,
              ),
          ],
        ),
      ),
      if (t >= 0.55)
        Opacity(
          opacity: _seg(t, 0.55, 0.7),
          child: _tile(
            s,
            w: 150,
            h: 150,
            filled: true,
            icon: Icons.photo,
            radius: 12,
          ),
        ),
      if (t < 0.55)
        // 가운데 줄 둘째 사진(고른 사진) 위
        Positioned(
          left: 100,
          top: 37,
          child: _finger(s, hold: _seg(t, 0.1, 0.5)),
        ),
    ],
  ),
};

// 0.15~0.55 동안 벌리고, 잠깐 멈췄다가 처음으로 돌아간다
double _pinchAmount(double t) =>
    Curves.easeInOut.transform(_seg(t, 0.15, 0.55)) * (1 - _seg(t, 0.85, 1));

Widget _pinch(ColorScheme s, double t, Widget child) {
  final spread = 30 + 50 * _pinchAmount(t);
  return Stack(
    alignment: Alignment.center,
    children: [
      child,
      Transform.translate(
        offset: Offset(-spread, spread * 0.6),
        child: _finger(s),
      ),
      Transform.translate(
        offset: Offset(spread, -spread * 0.6),
        child: _finger(s),
      ),
    ],
  );
}
