import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solo/api.dart';
import 'package:solo/connect/server_store.dart';

void main() {
  test('treats a bare host and port as an http server root', () {
    expect(
      ServerStore.parse(' 192.0.2.10:38550 ').toString(),
      'http://192.0.2.10:38550',
    );
  });

  test('keeps https and drops any path the person pasted', () {
    expect(
      ServerStore.parse('https://music.example.com/library?x=1').toString(),
      'https://music.example.com',
    );
  });

  test('rejects empty text and other schemes', () {
    expect(ServerStore.parse(''), isNull);
    expect(ServerStore.parse('ftp://music.example.com'), isNull);
    expect(ServerStore.parse('http://'), isNull);
  });

  test('sends no credentials when the server has no password', () {
    expect(Api(Uri.parse('http://192.0.2.1')).headers, isEmpty);
  });

  test('sends the password as HTTP basic auth', () {
    final header = Api(
      Uri.parse('http://192.0.2.1'),
      password: 'p:w',
    ).headers['authorization']!;
    expect(header, startsWith('Basic '));
    expect(utf8.decode(base64Decode(header.substring(6))), 'solo:p:w');
  });

  test('reads the android build the server offers', () {
    final b = AppBuild.fromJson({'version': '1.0.0+7', 'size': 22020096});
    expect(b.version, '1.0.0+7');
    expect(b.sizeLabel, '21.0 MB');
  });

  test('reads the server and one-time code from a pairing QR', () {
    final link = PairLink.parse(
      'solo://pair?server=https%3A%2F%2Fmusic.example.com&code=abc123',
    )!;
    expect(link.server.toString(), 'https://music.example.com');
    expect(link.code, 'abc123');
  });

  test('ignores QR codes that are not Solo pairing links', () {
    expect(PairLink.parse('https://example.com'), isNull);
    expect(
      PairLink.parse('solo://pair?server=ftp://example.com&code=a'),
      isNull,
    );
    expect(PairLink.parse('solo://pair?server=https://example.com'), isNull);
    expect(PairLink.parse('not a link'), isNull);
  });

  test('a paired device sends its token instead of a password', () {
    final api = Api(
      Uri.parse('http://192.0.2.1'),
      password: 'pw',
      token: 't0k',
    );
    expect(api.headers, {'authorization': 'Bearer t0k'});
  });
}
