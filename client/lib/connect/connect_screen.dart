import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import 'pair_dialog.dart';

/// 연결 탭입니다. 계정, 짝지은 기기, 앱 받기, 유튜브 계정, (앱에서는) 붙어 있는 서버를 한곳에서 다룹니다.
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.api, this.onChangeServer});

  final Api api;

  /// 앱에서만 있습니다. 기억한 서버를 지우고 처음 화면으로 돌아갑니다.
  final VoidCallback? onChangeServer;

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  Me? _me;
  List<Device>? _devices;
  AppBuild? _android;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<T?> _try<T>(Future<T> f) async {
    try {
      return await f;
    } on Exception {
      return null;
    }
  }

  Future<void> _load() async {
    final api = widget.api;
    final me = await _try(api.me());
    final results = await Future.wait([
      if (me?.owner ?? false) _try(api.devices()) else Future.value(null),
      kIsWeb ? _try(api.androidBuild()) : Future.value(null),
    ]);
    if (!mounted) return;
    setState(() {
      _me = me;
      _devices = results[0] as List<Device>?;
      _android = results[1] as AppBuild?;
    });
  }

  Future<void> _pair() async {
    final paired = await showPairDialog(context, widget.api);
    if (paired) await _load();
  }

  Future<void> _remove(Device d) async {
    final s = S.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.surface,
        content: Text(s.deviceRemoveAsk(d.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: Palette.secondary),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Palette.bad),
            child: Text(s.deviceRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _try(widget.api.removeDevice(d.id));
    await _load();
  }

  String _seen(S s, DateTime? at) {
    if (at == null) return s.seenAgo(s.justNow);
    final d = DateTime.now().difference(at);
    final when = d.inMinutes < 1
        ? s.justNow
        : d.inHours < 1
        ? s.minutesAgo(d.inMinutes)
        : d.inDays < 1
        ? s.hoursAgo(d.inHours)
        : s.daysAgo(d.inDays);
    return s.seenAgo(when);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final me = _me;
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: RefreshIndicator(
            onRefresh: _load,
            color: Palette.ink,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                Text(
                  s.tabConnect,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                  ),
                ),
                if (me != null && me.email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    s.signedInAs(me.email),
                    style: const TextStyle(fontSize: 13, color: Palette.faint),
                  ),
                ],
                if (_devices != null) ...[
                  _Header(
                    s.devicesTitle,
                    note: s.devicesNote,
                    action: s.deviceAdd,
                    onAction: _pair,
                  ),
                  _Group(
                    children: [
                      if (_devices!.isEmpty)
                        _Row(
                          icon: Icons.qr_code_2_rounded,
                          title: s.devicesNone,
                          sub: s.pairScanHint,
                        ),
                      for (final d in _devices!)
                        _Row(
                          icon: _deviceIcon(d.platform),
                          title: d.name,
                          sub: _seen(s, d.lastSeen),
                          trailing: _IconButton(
                            icon: Icons.link_off_rounded,
                            label: s.deviceRemove,
                            onTap: () => _remove(d),
                          ),
                        ),
                    ],
                  ),
                ],
                if (_android != null) ...[
                  _Header(s.appSection),
                  _Group(
                    children: [
                      _Row(
                        icon: Icons.android_rounded,
                        title: s.androidApp,
                        sub: [
                          s.androidAppNote,
                          if (_android!.version.isNotEmpty)
                            s.androidBuild(
                              _android!.version,
                              _android!.sizeLabel,
                            ),
                        ].join('\n'),
                        trailing: _IconButton(
                          icon: Icons.download_rounded,
                          label: s.androidGet,
                          filled: true,
                          onTap: () => launchUrl(
                            widget.api.apkUri,
                            webOnlyWindowName: '_self',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (widget.onChangeServer != null) ...[
                  _Header(s.serverSection),
                  _Group(
                    children: [
                      _Row(
                        icon: Icons.dns_rounded,
                        title: s.serverNow,
                        sub: widget.api.base.toString(),
                        trailing: _IconButton(
                          icon: Icons.swap_horiz_rounded,
                          label: s.serverChange,
                          onTap: widget.onChangeServer!,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),
                Text(
                  s.ownMusicNote,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Palette.faint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _deviceIcon(String platform) => switch (platform) {
    'android' || 'iOS' => Icons.smartphone_rounded,
    'macOS' || 'windows' || 'linux' => Icons.laptop_rounded,
    _ => Icons.devices_other_rounded,
  };
}

class _Header extends StatelessWidget {
  const _Header(this.title, {this.note, this.action, this.onAction});

  final String title;
  final String? note;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 0, 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Palette.secondary,
                ),
              ),
              if (note != null)
                Text(
                  note!,
                  style: const TextStyle(fontSize: 12, color: Palette.faint),
                ),
            ],
          ),
        ),
        if (action != null)
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
            label: Text(action!),
            style: FilledButton.styleFrom(
              backgroundColor: Palette.ink,
              foregroundColor: Palette.ground,
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Palette.line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, color: Palette.sunk),
          children[i],
        ],
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.sub,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String sub;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Palette.sunk,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: Palette.ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                sub,
                style: const TextStyle(fontSize: 12, color: Palette.faint),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ],
    ),
  );
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: Semantics(
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? Palette.butter : Palette.sunk,
          ),
          child: Icon(icon, size: 20, color: Palette.ink),
        ),
      ),
    ),
  );
}
