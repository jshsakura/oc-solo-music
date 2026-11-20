import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'l10n.dart';
import 'shell.dart';
import 'theme.dart';

void main() => runApp(SoloApp(api: Api.fromEnvironment()));

class SoloApp extends StatelessWidget {
  const SoloApp({super.key, required this.api});
  final Api api;

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
    home: Shell(api: api),
  );
}
