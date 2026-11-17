import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/data/repositories/signed_url_cache.dart';

void main() {
  test('없는 경로만 묶어 발급하고 만료 5분 전이면 다시 받는다', () async {
    var now = DateTime(2026, 11, 1, 9);
    final requests = <List<String>>[];
    final cache = SignedUrlCache((paths) async {
      requests.add(paths);
      return {for (final p in paths) p: '$p?t=${requests.length}'};
    }, now: () => now);

    expect(await cache.urls(['a', 'b']), {'a': 'a?t=1', 'b': 'b?t=1'});
    expect(await cache.urls(['a', 'c']), {'a': 'a?t=1', 'c': 'c?t=2'});
    expect(requests, [
      ['a', 'b'],
      ['c'],
    ]);

    now = now.add(const Duration(minutes: 56));
    expect((await cache.urls(['a']))['a'], 'a?t=3');
  });
}
