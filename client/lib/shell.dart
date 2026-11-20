import 'package:flutter/material.dart';

import 'add/add_screen.dart';
import 'add/jobs_watch.dart';
import 'api.dart';
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
  const Shell({super.key, required this.api});
  final Api api;

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
    AppTab.connect => _Later(
      title: S.of(context).tabConnect,
      note: S.of(context).connectLater,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab.index,
        children: [for (final t in AppTab.values) _screen(t)],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _jobs,
        builder: (_, _) => _BottomBar(
          current: _tab,
          busy: _jobs.busy,
          onPick: (t) => setState(() => _tab = t),
        ),
      ),
    );
  }
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
