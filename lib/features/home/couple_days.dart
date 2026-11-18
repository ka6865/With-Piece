import 'package:flutter/widgets.dart';

// 커플 앱 관례대로 사귄 날을 1일로 센다. 홈 머리글의 D+N이다(커플 디자인 4.2)
int daysTogether(DateTime startedOn, DateTime today) {
  final start = DateTime.utc(startedOn.year, startedOn.month, startedOn.day);
  final now = DateTime.utc(today.year, today.month, today.day);
  return now.difference(start).inDays + 1;
}

String formatStartedOn(DateTime day) =>
    '${day.year}.${day.month.toString().padLeft(2, '0')}.${day.day.toString().padLeft(2, '0')}';

// 닉네임 첫 글자. 이름이 없으면 대신 쓸 글자를 받는다
String initialOf(String? name, String fallback) {
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? fallback : trimmed.characters.first;
}
