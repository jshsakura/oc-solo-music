import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// index.html 의 `soloReady` 가 시작 화면을 천천히 걷어 냅니다.
void markReady() {
  if (!globalContext.has('soloReady')) return;
  globalContext.callMethod('soloReady'.toJS);
}
