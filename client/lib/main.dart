import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api.dart';
import 'connect/server_store.dart';
import 'connect/setup_screen.dart';
import 'l10n.dart';
import 'shell.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 앱에서는 화면을 꺼도 재생이 이어지고 잠금 화면과 알림에 조작 버튼이 뜹니다.
  // 웹은 브라우저가 미디어 세션을 맡고, 여기서 초기화하면 시작하다 멈춥니다.
  if (!kIsWeb) {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'app.solo.playback',
      androidNotificationChannelName: 'Solo',
      androidNotificationOngoing: true,
    );
  }
  runApp(SoloApp(api: await _startingApi()));
}

/// 웹은 자기를 내려준 서버를, 앱은 기억해 둔 서버를 씁니다. 앱이 처음이면 null 이라 주소부터 받습니다.
Future<Api?> _startingApi() async {
  const configured = String.fromEnvironment('SOLO_SERVER');
  if (configured.isNotEmpty) return Api(Uri.parse(configured));
  if (kIsWeb) return Api(Uri.parse(Uri.base.origin));
  final saved = await ServerStore.load();
  return saved == null
      ? null
      : Api(saved.address, password: saved.password, token: saved.token);
}

class SoloApp extends StatefulWidget {
  const SoloApp({super.key, required this.api});
  final Api? api;

  @override
  State<SoloApp> createState() => _SoloAppState();
}

class _SoloAppState extends State<SoloApp> {
  late Api? _api = widget.api;

  Future<void> _forgetServer() async {
    await ServerStore.clear();
    setState(() => _api = null);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Solo',
    debugShowCheckedModeBanner: false,
    supportedLocales: S.supported,
    localeListResolutionCallback: S.resolve,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    onGenerateTitle: (_) => 'Solo',
    builder: (context, child) => Theme(
      data: buildTheme(Localizations.localeOf(context).languageCode),
      child: child!,
    ),
    home: _api == null
        ? SetupScreen(onConnected: (api) => setState(() => _api = api))
        : Shell(
            key: ObjectKey(_api),
            api: _api!,
            onChangeServer: kIsWeb ? null : _forgetServer,
          ),
  );
}
