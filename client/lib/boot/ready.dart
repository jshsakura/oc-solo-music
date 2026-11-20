import 'ready_stub.dart' if (dart.library.js_interop) 'ready_web.dart' as impl;

/// 웹의 시작 화면에 첫 화면이 다 그려졌다고 알립니다. 앱에서는 아무 일도 하지 않습니다.
void markReady() => impl.markReady();
