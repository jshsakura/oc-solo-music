import 'package:web/web.dart' as web;

const isWeb = true;

/// SharedPreferences 웹판과 같은 이름(flutter. 접두사)을 써서 예전에 남은 값이 있으면 그대로 읽습니다.
String _name(String key) => 'flutter.$key';

String? read(String key) {
  final raw = web.window.localStorage.getItem(_name(key));
  if (raw == null) return null;
  // SharedPreferences 웹판은 문자열을 JSON 따옴표째 남깁니다.
  return raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')
      ? raw.substring(1, raw.length - 1)
      : raw;
}

void write(String key, String value) =>
    web.window.localStorage.setItem(_name(key), '"$value"');
