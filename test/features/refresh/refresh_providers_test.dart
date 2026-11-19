import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/data/repositories/refresh_repository.dart';
import 'package:woori_piece/features/refresh/refresh_providers.dart';
import 'package:woori_piece/features/scan/trip_candidates.dart';

TripCandidate candidate(int day) => TripCandidate(
  range: DateRange(DateTime(2026, 10, day), DateTime(2026, 10, day)),
  regionIds: const ['32060'],
  title: '',
);

void main() {
  final now = DateTime(2026, 11, 20, 9);

  test('상대 최신화 문구는 기록이 없으면 단정하지 않는다', () {
    expect(partnerRefreshText('준호', null, now), '준호님의 최신화 기록이 아직 없어요');
    expect(partnerRefreshText(null, null, now), '상대의 최신화 기록이 아직 없어요');
    expect(
      partnerRefreshText('준호', DateTime(2026, 11, 19, 23), now),
      '준호님은 어제 마지막으로 최신화했어요',
    );
    expect(
      partnerRefreshText('준호', DateTime(2026, 11, 20, 1), now),
      '준호님은 오늘 마지막으로 최신화했어요',
    );
  });

  test('같은 사람에게 1시간 안에는 다시 요청하지 못한다', () {
    final sent = RefreshState(
      requestedAt: now.subtract(const Duration(minutes: 30)),
      requestedBy: 'me',
    );
    expect(canRequestRefresh(sent, 'me', now), isFalse);
    expect(
      canRequestRefresh(sent, 'me', now.add(const Duration(hours: 1))),
      isTrue,
    );
    expect(canRequestRefresh(null, 'me', now), isTrue);
  });

  test('저장 뒤 결과는 새로 생긴 후보 기간만 센다', () {
    expect(newCandidateCount([candidate(1)], [candidate(1), candidate(3)]), 1);
    expect(newCandidateCount([candidate(1)], [candidate(1)]), 0);
    expect(newCandidateCount(null, [candidate(1)]), isNull);
    expect(sharingSavedMessage(2), '새 여행 2개를 찾았어요');
    expect(sharingSavedMessage(0), '새로 찾은 여행이 없어요');
    expect(sharingSavedMessage(null), '비교할 기록을 저장했어요');
  });
}
