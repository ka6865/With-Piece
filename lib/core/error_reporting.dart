import 'package:sentry_flutter/sentry_flutter.dart';

void configureSentry(
  SentryFlutterOptions options, {
  required String dsn,
  required String environment,
  String? installationId,
}) {
  options
    ..dsn = dsn
    ..environment = environment
    // 네이티브 전송은 Dart 필터를 거치지 않는다. Dart의 HTTP 전송으로 되돌린다.
    ..autoInitializeNativeSdk = false
    ..transport = SentryOptions().transport
    ..enableNativeCrashHandling = false
    ..enableAutoSessionTracking = false
    ..enableWatchdogTerminationTracking = false
    ..enableAppHangTracking = false
    ..sendDefaultPii = false
    ..sendClientReports = false
    ..reportPackages = false
    ..attachScreenshot = false
    ..attachViewHierarchy = false
    ..recordHttpBreadcrumbs = false
    ..captureFailedRequests = false
    ..enableAutoNativeBreadcrumbs = false
    ..enableUserInteractionBreadcrumbs = false
    ..enableAutoPerformanceTracing = false
    ..tracesSampleRate = null;
  options.beforeBreadcrumb = (_, _) => null;
  options.beforeSend = (event, hint) =>
      scrubEvent(event, hint, installationId: installationId);
  options.replay
    ..sessionSampleRate = 0
    ..onErrorSampleRate = 0;
}

// 예외 메시지와 SDK 추가 데이터에는 여행 제목이나 사용자 입력이 들어갈 수 있다.
SentryEvent? scrubEvent(
  SentryEvent event,
  Hint hint, {
  String? installationId,
}) {
  final exceptions = event.exceptions;
  if (exceptions == null || exceptions.isEmpty) return null;

  hint.attachments.clear();
  hint.screenshot = null;
  hint.viewHierarchy = null;
  final app = event.contexts.app;
  final device = event.contexts.device;
  final os = event.contexts.operatingSystem;

  return SentryEvent(
    eventId: event.eventId,
    timestamp: event.timestamp,
    platform: event.platform,
    release: event.release,
    dist: event.dist,
    environment: event.environment,
    level: event.level,
    user: installationId == null ? null : SentryUser(id: installationId),
    contexts: Contexts(
      app: app == null
          ? null
          : SentryApp(version: app.version, build: app.build),
      device: device == null ? null : SentryDevice(model: device.model),
      operatingSystem: os == null
          ? null
          : SentryOperatingSystem(name: os.name, version: os.version),
    ),
    exceptions: [
      for (final exception in exceptions)
        SentryException(
          type: _errorType(exception),
          value: null,
          stackTrace: _stackTrace(exception.stackTrace),
          mechanism: exception.mechanism == null
              ? null
              : Mechanism(
                  type: 'generic',
                  handled: exception.mechanism!.handled,
                ),
        ),
    ],
  );
}

String _errorType(SentryException exception) =>
    exception.throwable?.runtimeType.toString() ??
    (_symbol.hasMatch(exception.type ?? '') ? exception.type! : 'Error');

final _symbol = RegExp(r'^[a-zA-Z_$][\w.$]{0,119}$');
final _sourceFile = RegExp(r'^(?:(?:package:|dart:)?[\w./-]+)\.dart$');

SentryStackTrace? _stackTrace(SentryStackTrace? trace) {
  if (trace == null) return null;
  return SentryStackTrace(
    frames: [
      for (final frame in trace.frames)
        SentryStackFrame(
          fileName: _relativeSource(frame.fileName),
          function: frame.function,
          lineNo: frame.lineNo,
          colNo: frame.colNo,
          inApp: frame.inApp,
          instructionAddr: frame.instructionAddr,
        ),
    ],
  );
}

String? _relativeSource(String? source) {
  if (source == null ||
      source.startsWith('/') ||
      !_sourceFile.hasMatch(source)) {
    return null;
  }
  return source;
}
