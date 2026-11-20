import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'add/add_screen.dart';
import 'add/jobs_watch.dart';
import 'api.dart';
import 'connect/connect_screen.dart';
import 'home/home_screen.dart';
import 'l10n.dart';
import 'library_screen.dart';
import 'player/player_screen.dart';
import 'player_controller.dart';
import 'theme.dart';
import 'widgets/motion.dart';
import 'widgets/motion_math.dart';

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

  /// 새 탭이 들어오는 쪽입니다. 오른쪽 탭으로 가면 1, 왼쪽이면 -1 입니다.
  int _from = 1;
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
        playing: _ctl.playing,
        onPlay: (list, i) async {
          setState(() => _tab = AppTab.player);
          await _ctl.load(list, start: i, play: true);
        },
      ),
    ),
    AppTab.home => HomeScreen(
      api: widget.api,
      tracks: _tracks,
      loading: _loading,
      onPlay: (list, i) async {
        setState(() => _tab = AppTab.player);
        await _ctl.load(list, start: i, play: true);
      },
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
          pinned && t == AppTab.player
              ? const SizedBox.shrink()
              : _TabSwap(
                  active: t == current,
                  from: _from,
                  child: RepaintBoundary(child: _screen(t)),
                ),
      ],
    );
    void pick(AppTab t) {
      if (t == current) return;
      HapticFeedback.selectionClick();
      setState(() {
        _from = t.index > current.index ? 1 : -1;
        _tab = t;
      });
    }

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

  static const _sideRow = 50.0;

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
            Stack(
              children: [
                // 고른 탭 뒤의 검은 알약이 탭 사이를 미끄러져 옮겨 갑니다.
                AnimatedPositioned(
                  duration: reducedMotion(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  left: 12,
                  right: 12,
                  top: tabs.indexOf(current) * _sideRow + 2,
                  height: _sideRow - 4,
                  child: const DecoratedBox(
                    decoration: ShapeDecoration(
                      color: Palette.ink,
                      shape: StadiumBorder(),
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final t in tabs)
                      SizedBox(
                        height: _sideRow,
                        child: Padding(
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
                      ),
                  ],
                ),
              ],
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
    child: Pressable(
      onTap: onTap,
      scale: .96,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Badge(
              isLabelVisible: dot,
              smallSize: 8,
              backgroundColor: Palette.butter,
              child: _TabIcon(
                icon: icon,
                on: on,
                size: 22,
                color: on ? Palette.ground : Palette.secondary,
              ),
            ),
            const SizedBox(width: 12),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              style: TextStyle(
                fontSize: 14,
                fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                color: on ? Palette.ground : Palette.secondary,
              ),
              child: Text(label),
            ),
          ],
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
        child: Stack(
          children: [
            // 고른 탭의 아이콘과 이름을 함께 감싸는 버터색 알약이 탭 사이를 미끄러져 옮겨 갑니다.
            AnimatedAlign(
              duration: reducedMotion(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              alignment: Alignment(
                -1 + 2 * current.index / (AppTab.values.length - 1),
                0,
              ),
              child: FractionallySizedBox(
                widthFactor: 1 / AppTab.values.length,
                heightFactor: 1,
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Palette.butter,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Palette.butter.withValues(alpha: .45),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
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
                              child: _TabIcon(
                                icon: _tabOf(S.of(context), t).$1,
                                on: t == current,
                                size: 24,
                                color: t == current
                                    ? Palette.ink
                                    : Palette.faint,
                              ),
                            ),
                            const SizedBox(height: 3),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: t == current
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: t == current
                                    ? Palette.ink
                                    : Palette.faint,
                              ),
                              child: Text(_tabOf(S.of(context), t).$2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// 탭 아이콘입니다. 골라지는 순간 위로 톡 튀었다가 제자리로 내려앉습니다.
class _TabIcon extends StatelessWidget {
  const _TabIcon({
    required this.icon,
    required this.on,
    required this.size,
    required this.color,
  });

  final IconData icon;
  final bool on;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    // 켜질 때마다 0 에서 다시 시작하도록 상태에 따라 키를 바꿉니다.
    key: ValueKey(on),
    tween: Tween(begin: on ? 0 : 1, end: 1),
    duration: reducedMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 520),
    builder: (_, t, child) => Transform.translate(
      offset: Offset(0, -5 * (popScale(t) - 1) / .38),
      child: Transform.scale(scale: popScale(t), child: child),
    ),
    child: TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: const Duration(milliseconds: 220),
      builder: (_, c, _) => Icon(icon, size: size, color: c),
    ),
  );
}

/// 탭을 바꾸면 새 화면이 고른 쪽에서 살짝 밀려 들어오며 나타납니다.
/// 화면 자체는 IndexedStack 이 계속 쥐고 있어 상태가 그대로 남습니다.
class _TabSwap extends StatefulWidget {
  const _TabSwap({
    required this.active,
    required this.from,
    required this.child,
  });

  final bool active;
  final int from;
  final Widget child;

  @override
  State<_TabSwap> createState() => _TabSwapState();
}

class _TabSwapState extends State<_TabSwap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  late final Animation<double> _eased = CurvedAnimation(
    parent: _c,
    curve: Curves.easeOutCubic,
  );

  @override
  void didUpdateWidget(_TabSwap old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !reducedMotion(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _eased,
    builder: (_, child) {
      final v = _eased.value;
      if (v >= 1) return child!;
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(28.0 * widget.from * (1 - v), 0),
          child: Transform.scale(scale: .985 + .015 * v, child: child),
        ),
      );
    },
    child: widget.child,
  );
}
