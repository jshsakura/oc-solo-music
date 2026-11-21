import 'package:flutter_test/flutter_test.dart';
import 'package:solo/add/add_screen.dart';

void main() {
  test('picks only Suno song links out of copied text', () {
    final links = AddScreen.sunoLinks(
      '이거 들어봐 https://suno.com/s/AbCdEf123 그리고 '
      'https://www.suno.com/song/1a2b3c4d-0000-4000-8000-000000000000 '
      'https://example.com/s/nope https://suno.com/s/AbCdEf123',
    );
    expect(links, [
      'https://suno.com/s/AbCdEf123',
      'https://www.suno.com/song/1a2b3c4d-0000-4000-8000-000000000000',
    ]);
  });

  test('ignores text without Suno links', () {
    expect(AddScreen.sunoLinks('https://youtu.be/abc 그냥 글'), isEmpty);
  });
}
