import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'api.dart';
import 'boot/ready.dart';
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
  if (kIsWeb) _liftSplashWhenFontsArrive();
}

/// 웹은 글꼴을 받기 전의 첫 화면이 빈 네모로 보입니다. 첫 화면이 부른 글꼴이 다 오면 시작 화면을 걷습니다.
/// 글꼴이 늦어도 시작 화면이 남아 있지 않게 오래 기다리지 않습니다.
void _liftSplashWhenFontsArrive() {
  final binding = WidgetsBinding.instance;
  binding.addPostFrameCallback((_) async {
    try {
      await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 4));
    } catch (_) {
      // 글꼴을 못 받아도 앱은 기본 글꼴로 씁니다.
    }
    binding.addPostFrameCallback((_) => markReady());
    binding.scheduleFrame();
  });
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
