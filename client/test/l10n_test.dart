import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:solo/api.dart';
import 'package:solo/l10n.dart';

void main() {
  test('follows the first supported device language', () {
    expect(
      S.resolve(const [Locale('fr'), Locale('ja')], S.supported),
      const Locale('ja'),
    );
    expect(
      S.resolve(const [Locale('ko', 'KR')], S.supported),
      const Locale('ko'),
    );
  });

  test('falls back to English for unsupported languages', () {
    expect(S.resolve(const [Locale('de')], S.supported), const Locale('en'));
    expect(S.resolve(null, S.supported), const Locale('en'));
  });

  test('every language has every repeat label and api failure', () {
    for (final code in ['ko', 'en', 'ja']) {
      final s = S.forLanguage(code);
      expect(s.repeatLabels, hasLength(3));
      expect(s.repeatHints, hasLength(3));
      for (final f in ApiFail.values) {
        expect(s.apiFail(f), isNotEmpty);
      }
    }
  });

  test('adds the server reason after the screen message', () {
    final e = ApiException(
      ApiFail.add,
      status: 400,
      detail: '수노나 유튜브 주소가 아닙니다',
    );
    expect(S.forLanguage('ko').describe(e), contains('수노나'));
    final bare = ApiException(ApiFail.add, status: 400);
    expect(S.forLanguage('en').describe(bare), 'Could not add that link (400)');
    expect(S.forLanguage('ja').describe(StateError('x')), 'サーバーにつながりませんでした');
  });
}
