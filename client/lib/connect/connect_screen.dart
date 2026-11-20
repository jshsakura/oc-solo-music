import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';

/// 연결 탭입니다. 웹에서는 안드로이드 앱을 내려받게 하고, 앱에서는 붙어 있는 서버를 보여줍니다.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.api, this.onChangeServer});

  final Api api;

  /// 앱에서만 있습니다. 기억한 서버를 지우고 처음 화면으로 돌아갑니다.
  final VoidCallback? onChangeServer;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final Future<AppBuild?> _android = kIsWeb
      ? widget.api.androidBuild().then<AppBuild?>(
          (b) => b,
          onError: (_) => null,
        )
      : Future.value(null);

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Text(
            s.tabConnect,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          if (widget.onChangeServer != null)
            _Card(
              icon: Icons.dns_outlined,
              title: s.serverNow,
              lines: [widget.api.base.toString()],
              action: s.serverChange,
              actionIcon: Icons.swap_horiz_rounded,
              onAction: widget.onChangeServer!,
            ),
          FutureBuilder<AppBuild?>(
            future: _android,
            builder: (context, snap) {
              final build = snap.data;
              if (build == null) return const SizedBox.shrink();
              return _Card(
                icon: Icons.android_rounded,
                title: s.androidApp,
                lines: [
                  s.androidAppNote,
                  if (build.version.isNotEmpty)
                    s.androidBuild(build.version, build.sizeLabel),
                ],
                action: s.androidGet,
                actionIcon: Icons.download_rounded,
                onAction: () =>
                    launchUrl(widget.api.apkUri, webOnlyWindowName: '_self'),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
            child: Text(
              s.connectLater,
              style: const TextStyle(fontSize: 12, color: Palette.faint),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.lines,
    required this.action,
    required this.actionIcon,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final List<String> lines;
  final String action;
  final IconData actionIcon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
    decoration: BoxDecoration(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Palette.line),
    ),
    child: Row(
      children: [
        Icon(icon, size: 22, color: Palette.ink),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final l in lines)
                Text(
                  l,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Palette.secondary,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Semantics(
          button: true,
          label: action,
          child: GestureDetector(
            onTap: onAction,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Palette.butter,
              ),
              child: Icon(actionIcon, size: 22, color: Palette.ink),
            ),
          ),
        ),
      ],
    ),
  );
}
