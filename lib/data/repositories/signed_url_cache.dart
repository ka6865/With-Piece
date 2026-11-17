// 사진 서명 URL. 화면에 보이는 경로만 묶어 발급하고 만료 5분 전에 다시 받는다.
// DB에는 URL을 저장하지 않는다(설계 8.2)
class SignedUrlCache {
  SignedUrlCache(this._sign, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const ttl = Duration(hours: 1);
  static const refreshBefore = Duration(minutes: 5);

  final Future<Map<String, String>> Function(List<String> paths) _sign;
  final DateTime Function() _now;
  final _cache = <String, ({String url, DateTime expiresAt})>{};

  Future<Map<String, String>> urls(List<String> paths) async {
    final now = _now();
    final stale = <String>[];
    for (final path in paths) {
      final cached = _cache[path];
      if (cached == null || cached.expiresAt.difference(now) <= refreshBefore) {
        stale.add(path);
      }
    }
    if (stale.isNotEmpty) {
      final signed = await _sign(stale);
      for (final MapEntry(key: path, value: url) in signed.entries) {
        _cache[path] = (url: url, expiresAt: now.add(ttl));
      }
    }
    return {
      for (final path in paths)
        if (_cache[path] case final c?) path: c.url,
    };
  }
}
