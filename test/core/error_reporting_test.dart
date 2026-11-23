import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:woori_piece/core/error_reporting.dart';

void main() {
  test('오류 종류와 별도로 제공한 진단 ID만 보낸다', () {
    final event = SentryEvent(
      exceptions: [SentryException(type: 'StateError', value: 'a@b.com')],
      user: SentryUser(
        id: 'account-id',
        email: 'a@b.com',
        ipAddress: '1.2.3.4',
      ),
      request: SentryRequest(url: 'https://example.com/photos'),
    );
    final out = scrubEvent(event, Hint(), installationId: 'install-1')!;
    expect(out.exceptions!.single.type, 'StateError');
    expect(out.exceptions!.single.value, isNull);
    expect(out.user!.id, 'install-1');
    expect(out.user!.email, isNull);
    expect(out.user!.ipAddress, isNull);
    expect(out.request, isNull);
  });

  test('메시지 이벤트와 부착 파일을 보내지 않는다', () {
    expect(
      scrubEvent(SentryEvent(message: SentryMessage('메모')), Hint()),
      isNull,
    );
    final event = SentryEvent(
      exceptions: [SentryException(type: 'StateError', value: null)],
    );
    final hint = Hint.withAttachment(SentryAttachment.fromIntList([1], 'a'));
    expect(scrubEvent(event, hint), isNotNull);
    expect(hint.attachments, isEmpty);
  });

  test('허용한 항목만 남기고 계정 ID와 자유 입력을 버린다', () {
    final event = SentryEvent(
      message: SentryMessage('비공개 여행 제목', params: ['비공개 메모']),
      exceptions: [
        SentryException(
          type: 'StateError',
          value: '비공개 댓글',
          stackTrace: SentryStackTrace(
            frames: [
              SentryStackFrame(
                fileName: 'package:woori_piece/main.dart',
                lineNo: 42,
                vars: {'memo': '비공개 변수'},
              ),
            ],
          ),
        ),
      ],
      user: SentryUser(id: 'account-id'),
      tags: {'memo': '비공개 태그'},
      breadcrumbs: [Breadcrumb(message: '비공개 기록')],
    );
    final json = scrubEvent(event, Hint())!.toJson();
    expect(json.toString(), isNot(contains('비공개')));
    expect(json.toString(), isNot(contains('account-id')));
    expect(json.toString(), contains('StateError'));
    expect(json.toString(), contains('main.dart'));
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
    expect(options.autoInitializeNativeSdk, isFalse);
    expect(options.enableAutoSessionTracking, isFalse);
    expect(options.enableNativeCrashHandling, isFalse);
    expect(options.sendClientReports, isFalse);
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
