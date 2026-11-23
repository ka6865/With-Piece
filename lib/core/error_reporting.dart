import 'package:sentry_flutter/sentry_flutter.dart';

// 오류 수집(설계 12.1). 오류 종류·메시지·추적 정보와 앱·기기 버전만 보내고, 사용자와
// 연결되거나 위치를 짐작할 수 있는 값은 보내기 직전에 빼거나 가린다

void configureSentry(
  SentryFlutterOptions options, {
  required String dsn,
  required String environment,
}) {
  options
    ..dsn = dsn
    ..environment = environment
    ..sendDefaultPii = false
    ..attachScreenshot = false
    ..attachViewHierarchy = false
    // iOS 쪽 자동 기록에는 네트워크 주소(서명 URL)가 들어간다
    ..enableAutoNativeBreadcrumbs = false
    // 누른 위젯의 글자(여행 제목 등)가 기록된다
    ..enableUserInteractionBreadcrumbs = false
    ..enableAutoPerformanceTracing = false
    ..tracesSampleRate = null
    ..beforeSend = scrubEvent
    ..beforeBreadcrumb = scrubBreadcrumb;
  options.replay
    ..sessionSampleRate = 0
    ..onErrorSampleRate = 0;
}

// 앞에서부터 차례로 바꾼다. 주소 안의 토큰·ID가 먼저 주소째 사라지게 주소를 맨 앞에 둔다
final _patterns = <(RegExp, String)>[
  (RegExp(r'https?://\S+'), '[url]'),
  (RegExp(r'eyJ[\w-]*\.[\w-]+\.[\w-]+'), '[token]'),
  (RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '[email]'),
  (
    RegExp(
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
    ),
    '[id]',
  ),
  // 경위도(소수점 아래 4자리 이상)
  (RegExp(r'-?\d{1,3}\.\d{4,}'), '[coord]'),
  // 병합 조각 id(시도 2자리-대표구 5자리)와 조각 코드(5자리)
  (RegExp(r'\b\d{2}-\d{5}\b'), '[region]'),
  (RegExp(r'\b\d{5}\b'), '[region]'),
];

String scrubText(String text) {
  var out = text;
  for (final (pattern, replacement) in _patterns) {
    out = out.replaceAll(pattern, replacement);
  }
  return out;
}

SentryEvent? scrubEvent(SentryEvent event, Hint hint) {
  final message = event.message;
  if (message != null) {
    message.formatted = scrubText(message.formatted);
  }
  for (final exception in event.exceptions ?? const <SentryException>[]) {
    if (exception.value case final value?) exception.value = scrubText(value);
  }
  if (event.transaction case final transaction?) {
    event.transaction = scrubText(transaction);
  }
  // 계정과 이어지지 않는 설치별 익명 ID만 남긴다. 몇 명이 겪었는지 대략 세는 데 쓴다.
  // 이메일·IP·이름은 보내지 않는다(사용자 결정: 최소한)
  final installId = event.user?.id;
  event
    ..user = installId == null ? null : SentryUser(id: installId)
    ..request = null;
  return event;
}

Breadcrumb? scrubBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  if (breadcrumb == null) return null;
  final category = breadcrumb.category ?? '';
  if (breadcrumb.type == 'http' ||
      category.startsWith('http') ||
      category == 'navigation' ||
      category.startsWith('ui.')) {
    return null;
  }
  if (breadcrumb.message case final message?) {
    breadcrumb.message = scrubText(message);
  }
  breadcrumb.data = null;
  return breadcrumb;
}
