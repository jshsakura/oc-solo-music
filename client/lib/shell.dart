import 'package:flutter/material.dart';

import 'add/add_screen.dart';
import 'add/jobs_watch.dart';
import 'api.dart';
import 'connect/connect_screen.dart';
import 'l10n.dart';
import 'library_screen.dart';
import 'player/player_screen.dart';
import 'player_controller.dart';
import 'theme.dart';

enum AppTab { home, library, player, add, connect }

(IconData, String) _tabOf(S s, AppTab t) => switch (t) {
  AppTab.home => (Icons.home_outlined, s.tabHome),
  AppTab.library => (Icons.album_outlined, s.tabLibrary),
  AppTab.player => (Icons.radio_button_checked_rounded, s.tabPlayer),
  AppTab.add => (Icons.add_circle_outline_rounded, s.tabAdd),
  AppTab.connect => (Icons.devices_outlined, s.tabConnect),
};

/// 앱 전체 틀입니다. 곡 목록을 한 번 받아 보관함과 재생 화면이 같이 씁니다.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.api, this.onChangeServer});
  final Api api;

  /// 앱에서만 있습니다. 다른 서버로 바꿀 때 부릅니다.
  final VoidCallback? onChangeServer;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late final PlayerController _ctl = PlayerController(widget.api);
  late final JobsWatch _jobs = JobsWatch(widget.api, onFinished: _load);
  AppTab _tab = AppTab.player;
  List<Track> _tracks = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _ctl.addListener(_syncLikes);
    _load();
    _jobs.start();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.api.language = Localizations.localeOf(context).languageCode;
  }

  @override
  void dispose() {
    _ctl.removeListener(_syncLikes);
    _ctl.dispose();
    _jobs.dispose();
    super.dispose();
  }

  /// 재생 화면에서 바꾼 좋아요를 보관함 목록에도 반영합니다.
  void _syncLikes() {
    final cur = _ctl.current;
    if (cur == null) return;
    final i = _tracks.indexWhere((t) => t.id == cur.id);
    if (i >= 0 && _tracks[i].liked != cur.liked) {
      setState(
        () => _tracks = [for (final t in _tracks) t.id == cur.id ? cur : t],
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tracks = await widget.api.tracks();
      if (!mounted) return;
      setState(() => _tracks = tracks);
      if (_ctl.queue.isEmpty && tracks.isNotEmpty) await _ctl.load(tracks);
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _screen(AppTab tab) => switch (tab) {
    AppTab.player => PlayerScreen(ctl: _ctl),
    AppTab.library => ListenableBuilder(
      listenable: _ctl,
      builder: (_, _) => LibraryScreen(
        api: widget.api,
        tracks: _tracks,
        loading: _loading,
        error: _error == null ? null : S.of(context).describe(_error!),
        onRetry: _load,
        currentId: _ctl.current?.id,
        onPlay: (list, i) async {
          setState(() => _tab = AppTab.player);
          await _ctl.load(list, start: i, play: true);
        },
      ),
    ),
    AppTab.home => _Later(
      title: S.of(context).tabHome,
      note: S.of(context).homeLater,
    ),
    AppTab.add => AddScreen(api: widget.api, watch: _jobs),
    AppTab.connect => ConnectScreen(
      api: widget.api,
      onChangeServer: widget.onChangeServer,
    ),
  };

  /// 이 폭부터 옆 메뉴를 씁니다(태블릿 가로, 데스크톱).
  static const sideFrom = 900.0;

  /// 이 폭부터는 턴테이블을 오른쪽에 붙여 두고 다른 화면을 함께 봅니다.
  static const pinnedPlayerFrom = 1180.0;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final side = width >= sideFrom;
    final pinned = width >= pinnedPlayerFrom;
    final tabs = [
      for (final t in AppTab.values)
        if (!(pinned && t == AppTab.player)) t,
    ];
    final current = pinned && _tab == AppTab.player ? AppTab.library : _tab;
    final pages = IndexedStack(
      index: current.index,
      children: [
        for (final t in AppTab.values)
          pinned && t == AppTab.player ? const SizedBox.shrink() : _screen(t),
      ],
    );
    void pick(AppTab t) => setState(() => _tab = t);
    if (!side) {
      return Scaffold(
        body: pages,
        bottomNavigationBar: ListenableBuilder(
          listenable: _jobs,
          builder: (_, _) =>
              _BottomBar(current: current, busy: _jobs.busy, onPick: pick),
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          ListenableBuilder(
            listenable: _jobs,
            builder: (_, _) => _SideBar(
              tabs: tabs,
              current: current,
              busy: _jobs.busy,
              onPick: pick,
            ),
          ),
          Expanded(child: pages),
          if (pinned)
            Container(
              width: 420,
              clipBehavior: Clip.hardEdge,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: Palette.line)),
              ),
              child: PlayerScreen(ctl: _ctl),
            ),
        ],
      ),
    );
  }
}

/// 넓은 화면의 왼쪽 메뉴입니다. 휴대폰의 아래 막대와 같은 탭을 세로로 늘어놓습니다.
class _SideBar extends StatelessWidget {
  const _SideBar({
    required this.tabs,
    required this.current,
    required this.busy,
    required this.onPick,
  });

  final List<AppTab> tabs;
  final AppTab current;
  final bool busy;
  final ValueChanged<AppTab> onPick;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Container(
      width: 224,
      decoration: const BoxDecoration(
        color: Palette.surface,
        border: Border(right: BorderSide(color: Palette.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'solo'),
                    TextSpan(
                      text: '.',
                      style: letterStyle(34).copyWith(color: Palette.butter),
                    ),
                  ],
                ),
                style: letterStyle(34),
              ),
            ),
            for (final t in tabs)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 2,
                ),
                child: _SideItem(
                  icon: _tabOf(s, t).$1,
                  label: _tabOf(s, t).$2,
                  on: t == current,
                  dot: busy && t == AppTab.add,
                  onTap: () => onPick(t),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    required this.on,
    required this.dot,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool on;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: Material(
      color: on ? Palette.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        borderRadius: BorderRadius.circular(100),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Badge(
                isLabelVisible: dot,
                smallSize: 8,
                backgroundColor: Palette.butter,
                child: Icon(
                  icon,
                  size: 22,
                  color: on ? Palette.ground : Palette.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                  color: on ? Palette.ground : Palette.secondary,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.current,
    required this.busy,
    required this.onPick,
  });
  final AppTab current;

  /// 녹음이나 받기가 돌고 있으면 추가 탭에 점을 찍습니다.
  final bool busy;
  final ValueChanged<AppTab> onPick;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Palette.surface,
      border: Border(top: BorderSide(color: Palette.line)),
    ),
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 58,
        child: Row(
          children: [
            for (final t in AppTab.values)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: t == current,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPick(t),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Badge(
                          isLabelVisible: busy && t == AppTab.add,
                          smallSize: 8,
                          backgroundColor: Palette.butter,
                          child: Icon(
                            _tabOf(S.of(context), t).$1,
                            size: 24,
                            color: t == current ? Palette.ink : Palette.faint,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _tabOf(S.of(context), t).$2,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: t == current
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: t == current ? Palette.ink : Palette.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Later extends StatelessWidget {
  const _Later({required this.title, required this.note});
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: const TextStyle(fontSize: 13, color: Palette.faint),
          ),
        ],
      ),
    ),
  );
}
