import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woori_piece/app/theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  for (final (name, scheme) in [('밝은', lightScheme), ('어두운', darkScheme)]) {
    group('$name 테마 대비(커플 디자인 4.1)', () {
      test('본문·보조 글자와 주 색 글자는 4.5:1 이상', () {
        for (final (fg, bg) in [
          (scheme.onSurface, scheme.surface),
          (scheme.onSurfaceVariant, scheme.surface),
          (scheme.onSurfaceVariant, scheme.surfaceContainerLowest),
          (scheme.primary, scheme.surface),
          (scheme.primary, scheme.surfaceContainerLowest),
          (scheme.onPrimary, scheme.primary),
          (scheme.onPrimaryContainer, scheme.primaryContainer),
        ]) {
          expect(
            contrast(fg, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$fg / $bg',
          );
        }
      });

      test('지도 세 상태의 테두리는 인접 면과 3:1 이상', () {
        for (final (line, face) in [
          // 채운 조각 테두리
          (scheme.onPrimaryContainer, scheme.primaryContainer),
          // 생활권 테두리·빗금
          (scheme.tertiary, scheme.primaryContainer),
          (scheme.tertiary, scheme.surfaceContainerHighest),
          // 빈 조각 점선
          (scheme.outline, scheme.surfaceContainerHighest),
        ]) {
          expect(
            contrast(line, face),
            greaterThanOrEqualTo(3),
            reason: '$line / $face',
          );
        }
      });
    });
  }
}
