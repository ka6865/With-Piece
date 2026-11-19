import 'dart:collection';

// 사진 서명 URL. 화면에 보이는 경로만 묶어 발급하고 만료 5분 전에 다시 받는다.
// DB에는 URL을 저장하지 않는다(설계 8.2)
class SignedUrlCache {
  SignedUrlCache(this._sign, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const ttl = Duration(hours: 1);
  static const refreshBefore = Duration(minutes: 5);
  static const maxBatchSize = 100;
  static const maxEntries = 512;

  final Future<Map<String, String>> Function(List<String> paths) _sign;
  final DateTime Function() _now;
  final _cache = <String, ({String url, DateTime expiresAt})>{};

  Future<Map<String, String>> urls(List<String> paths) async {
    final now = _now();
    final stale = <String>[];
    final result = <String, String>{};
    for (final path in LinkedHashSet<String>.of(paths)) {
      final cached = _cache.remove(path);
      if (cached == null || cached.expiresAt.difference(now) <= refreshBefore) {
        stale.add(path);
      } else {
        _cache[path] = cached;
        result[path] = cached.url;
      }
    }
    for (var start = 0; start < stale.length; start += maxBatchSize) {
      final batch = stale.skip(start).take(maxBatchSize).toList();
      final signed = await _sign(batch);
      for (final MapEntry(key: path, value: url) in signed.entries) {
        if (!batch.contains(path)) continue;
        final entry = (url: url, expiresAt: _now().add(ttl));
        _cache[path] = entry;
        result[path] = url;
        if (_cache.length > maxEntries) _cache.remove(_cache.keys.first);
      }
    }
    return result;
  }
}
