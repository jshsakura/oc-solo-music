import 'package:shared_preferences/shared_preferences.dart';

import 'local_value_web.dart'
    if (dart.library.io) 'local_value_io.dart'
    as platform;

/// 기기에 작은 값 하나를 기억해 둡니다. 웹에서는 브라우저 저장소에 바로 쓰고, 앱에서는
/// SharedPreferences 를 씁니다. 웹 빌드에서 SharedPreferences 가 아무것도 저장하지 못해
/// 홈 보기가 새로고침마다 처음으로 돌아가던 것을 막습니다.
Future<String?> readLocal(String key) async {
  try {
    if (platform.isWeb) return platform.read(key);
    return (await SharedPreferences.getInstance()).getString(key);
  } on Object {
    return null;
  }
}

Future<void> writeLocal(String key, String value) async {
  try {
    if (platform.isWeb) return platform.write(key, value);
    await (await SharedPreferences.getInstance()).setString(key, value);
  } on Object {
    // 저장하지 못해도 지금 고른 값은 그대로 씁니다.
  }
}
