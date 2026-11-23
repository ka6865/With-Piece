import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:woori_piece/core/error_reporting.dart';

void main() {
  test('메시지에서 주소, 토큰, 이메일, ID, 조각 코드, 좌표를 가린다', () {
    const raw =
        'GET https://abc.supabase.co/storage/v1/object/sign/photos/x.heic?token=eyJhbGciOi.eyJzdWIi.sig '
        'user a@b.com trip 3f2b1c4d-1111-2222-3333-444455556666 '
        'region 32060 merged 38-38111 at 37.56651, 126.97801';
    final out = scrubText(raw);
    expect(out, isNot(contains('supabase.co')));
    expect(out, isNot(contains('eyJ')));
    expect(out, isNot(contains('a@b.com')));
    expect(out, isNot(contains('3f2b1c4d')));
    expect(out, isNot(contains('32060')));
    expect(out, isNot(contains('38111')));
    expect(out, isNot(contains('37.56651')));
    expect(out, isNot(contains('126.97801')));
    // 원인을 알 수 있는 말은 남긴다
    expect(out, contains('trip'));
    expect(out, contains('region'));
  });

  test('보내기 전에 사용자 정보와 요청을 빼고 메시지와 예외를 가린다', () {
    final event = SentryEvent(
      message: SentryMessage('failed for a@b.com'),
      exceptions: [
        SentryException(
          type: 'PostgrestException',
          value: 'trip 3f2b1c4d-1111-2222-3333-444455556666 not found',
        ),
      ],
      user: SentryUser(id: 'install-1', email: 'a@b.com', ipAddress: '1.2.3.4'),
      request: SentryRequest(url: 'https://abc.supabase.co/rest/v1/trips'),
      transaction: '/trips/3f2b1c4d-1111-2222-3333-444455556666',
    );
    final out = scrubEvent(event, Hint())!;
    expect(out.message!.formatted, isNot(contains('a@b.com')));
    expect(out.exceptions!.single.type, 'PostgrestException');
    expect(out.exceptions!.single.value, isNot(contains('3f2b1c4d')));
    // 설치별 익명 ID만 남는다
    expect(out.user!.id, 'install-1');
    expect(out.user!.email, isNull);
    expect(out.user!.ipAddress, isNull);
    expect(out.request, isNull);
    expect(out.transaction, isNot(contains('3f2b1c4d')));
  });

  test('네트워크, 화면 이동, 터치 기록은 버리고 나머지는 가려서 남긴다', () {
    expect(
      scrubBreadcrumb(
        Breadcrumb.http(url: Uri.parse('https://x.co'), method: 'GET'),
        Hint(),
      ),
      isNull,
    );
    expect(
      scrubBreadcrumb(
        Breadcrumb(category: 'navigation', message: '/regions/32060'),
        Hint(),
      ),
      isNull,
    );
    expect(
      scrubBreadcrumb(
        Breadcrumb(category: 'ui.click', message: '속초 여행'),
        Hint(),
      ),
      isNull,
    );
    final kept = scrubBreadcrumb(
      Breadcrumb(
        category: 'app.lifecycle',
        message: 'region 32060',
        data: {'k': 'v'},
      ),
      Hint(),
    )!;
    expect(kept.message, isNot(contains('32060')));
    expect(kept.data, isNull);
  });

  test('화면 캡처, 화면 구조, 성능 추적, 자동 기록을 끈다', () {
    final options = SentryFlutterOptions();
    configureSentry(
      options,
      dsn: 'https://k@o.ingest.sentry.io/1',
      environment: 'dev-cloud',
    );
    expect(options.dsn, 'https://k@o.ingest.sentry.io/1');
    expect(options.environment, 'dev-cloud');
    expect(options.sendDefaultPii, isFalse);
    expect(options.attachScreenshot, isFalse);
    expect(options.attachViewHierarchy, isFalse);
    expect(options.enableAutoNativeBreadcrumbs, isFalse);
    expect(options.enableUserInteractionBreadcrumbs, isFalse);
    expect(options.enableAutoPerformanceTracing, isFalse);
    expect(options.tracesSampleRate, isNull);
    expect(options.replay.sessionSampleRate ?? 0, 0);
    expect(options.replay.onErrorSampleRate ?? 0, 0);
    expect(options.beforeSend, isNotNull);
    expect(options.beforeBreadcrumb, isNotNull);
  });
}
