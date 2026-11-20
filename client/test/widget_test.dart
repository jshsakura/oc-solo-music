import 'package:flutter_test/flutter_test.dart';
import 'package:solo/api.dart';
import 'package:solo/theme.dart';

void main() {
  test(
    'reads a track from the server shape and falls back on missing fields',
    () {
      final t = Track.fromJson({
        'id': 'a',
        'title': 'clair de lune',
        'duration': 311.4,
        'cover': true,
      });
      expect(t.letter, 'C');
      expect(t.artist, '');
      expect(t.hasCover, isTrue);
      expect(t.liked, isFalse);
      expect(t.withLiked(true).liked, isTrue);
    },
  );

  test('uses a question mark when the title is empty', () {
    expect(Track.fromJson({'id': 'x'}).letter, '?');
  });

  test('formats seconds as minutes and seconds', () {
    expect(formatTime(311.9), '5:11');
    expect(formatTime(double.nan), '0:00');
    expect(formatTime(-3), '0:00');
  });

  test('picks the same sleeve colour for the same id', () {
    expect(Palette.sleeveOf('song-1'), Palette.sleeveOf('song-1'));
  });

  test('escapes ids in media addresses', () {
    final api = Api(Uri.parse('http://192.0.2.1:38550'));
    expect(
      api.audioUri('a b/c').toString(),
      'http://192.0.2.1:38550/api/audio/a%20b%2Fc',
    );
  });

  test('reads a job and tells running from waiting', () {
    final j = Job.fromJson({
      'id': 'j1',
      'kind': 'suno',
      'status': 'recording',
      'url': 'https://example.com/v',
      'progress': 0.4,
    });
    expect(j.isRunning, isTrue);
    expect(j.isActive, isTrue);
    expect(j.label, 'https://example.com/v');
    final q = Job.fromJson({'id': 'j2', 'status': 'queued', 'title': 'song'});
    expect(q.isRunning, isFalse);
    expect(q.isActive, isTrue);
    expect(q.label, 'song');
    expect(Job.fromJson({'id': 'j3', 'status': 'done'}).isActive, isFalse);
  });
}
