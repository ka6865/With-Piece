import 'package:flutter/material.dart';

// 처음 쓰는 사람을 위한 안내(2026-11-23 설계 ④). 연결 전에는 소개 카드, 연결 뒤에는
// 화면마다 ? 도움말이다. 서버를 쓰지 않는다

typedef GuideCard = ({IconData icon, String title, String body});

const introCards = <GuideCard>[
  (
    icon: Icons.extension,
    title: '우리들의 조각',
    body:
        '둘이 함께 다녀온 대한민국 곳곳을 퍼즐 조각으로 채워요. '
        '조각마다 그날의 사진이 남아요.',
  ),
  (
    icon: Icons.link,
    title: '먼저 연인과 연결해요',
    body:
        '한 사람이 "초대 코드 만들기"로 코드를 만들어 보내고, '
        '다른 사람이 "받은 코드 입력"에 넣으면 연결돼요. '
        '코드는 3일 동안 한 번만 쓸 수 있고, 새로고침하면 새 코드로 바뀌어요.',
  ),
  (
    icon: Icons.auto_awesome,
    title: '사진으로 저절로 채워져요',
    body:
        '두 사람이 같은 날 같은 곳에서 찍은 사진을 찾아 여행 후보로 보여줘요. '
        '사진 위치는 휴대폰 안에서만 쓰고, 서버에는 날짜와 지역만 보내요.',
  ),
  (
    icon: Icons.photo_album,
    title: '함께 꾸미는 앨범',
    body:
        '여행에 사진을 올리고 조각마다 대표 사진을 골라 지도를 채워요. '
        '두 사람 모두 같은 지도와 앨범을 봐요.',
  ),
];

enum HelpTopic {
  home('홈', [
    '함께한 날과 지금까지 채운 조각 수를 보여줘요.',
    '"우리의 조각" 카드를 누르면 지도로 가요.',
    '새 여행 후보가 생기면 여기서 알려줘요. 확인하면 조각이 채워져요.',
  ]),
  map('지도', [
    '시도를 누르면 그 안의 시군구 조각이 보여요.',
    '채운 조각을 누르면 그곳 사진을, 빈 조각을 누르면 여행을 직접 만들 수 있어요.',
    '조각을 길게 누르면 생활권과 여행지를 바꿀 수 있어요.',
    '두 손가락으로 지도를 확대·축소해요.',
  ]),
  album('앨범', [
    '여행별로 두 사람의 사진을 모아 봐요.',
    '사진을 누르면 크게 보고, 사진 목록은 두 손가락으로 칸 크기를 바꿀 수 있어요.',
    '사진을 고를 때 길게 누르면 크게 보며 고를 수 있어요.',
  ]);

  const HelpTopic(this.title, this.lines);

  final String title;
  final List<String> lines;
}

// 화면 오른쪽 위의 ? 버튼. 누르면 그 화면 설명을 아래에서 짧게 보여준다
class HelpButton extends StatelessWidget {
  const HelpButton({super.key, required this.topic});

  final HelpTopic topic;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '도움말',
    icon: const Icon(Icons.help_outline),
    onPressed: () => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${topic.title} 도움말',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (final line in topic.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('· $line'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

// 연결 전 소개 카드. 넘기며 읽고 마지막 장에서 시작한다
class IntroPage extends StatefulWidget {
  const IntroPage({super.key});

  // 기기에 한 번만 자동으로 띄운다
  static const seenKey = 'guide_intro_seen';

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage> {
  final _pages = PageController();
  var _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _index == introCards.length - 1;
    return Scaffold(
      appBar: AppBar(
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('건너뛰기'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (index) => setState(() => _index = index),
                children: [
                  for (final card in introCards)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            card.icon,
                            size: 72,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            card.title,
                            style: theme.textTheme.headlineSmall,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            card.body,
                            style: theme.textTheme.bodyLarge,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Text(
              '${_index + 1} / ${introCards.length}',
              style: theme.textTheme.bodySmall,
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: last
                      ? () => Navigator.pop(context)
                      : () => _pages.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        ),
                  child: Text(last ? '시작하기' : '다음'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
