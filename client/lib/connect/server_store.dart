import 'package:shared_preferences/shared_preferences.dart';

/// 앱이 붙을 서버 주소와 비밀번호를 기기에 기억합니다. 웹은 자기를 내려준 서버를 쓰므로 쓰지 않습니다.
class ServerStore {
  static const _addressKey = 'server.address';
  static const _passwordKey = 'server.password';

  static Future<({Uri address, String password})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final address = parse(prefs.getString(_addressKey) ?? '');
    if (address == null) return null;
    return (address: address, password: prefs.getString(_passwordKey) ?? '');
  }

  static Future<void> save(Uri address, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_addressKey, address.toString());
    await prefs.setString(_passwordKey, password);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_addressKey);
    await prefs.remove(_passwordKey);
  }

  /// 사람이 넣은 주소를 서버 뿌리 주소로 정리합니다. 스킴이 없으면 http 로 봅니다.
  static Uri? parse(String text) {
    var t = text.trim();
    if (t.isEmpty) return null;
    if (!t.contains('://')) t = 'http://$t';
    final u = Uri.tryParse(t);
    if (u == null || u.host.isEmpty) return null;
    if (u.scheme != 'http' && u.scheme != 'https') return null;
    return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null);
  }
}
