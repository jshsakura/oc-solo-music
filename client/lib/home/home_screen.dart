import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../l10n.dart';
import '../store/local_value.dart';
import '../widgets/scroll_header.dart';
import '../theme.dart';
import '../widgets/skeleton.dart';
import '../widgets/track_menu.dart';
import 'crate_math.dart';
import 'crate_stage.dart';
import 'jukebox.dart';
import 'shelf_grid.dart';

String _crateName(S s, HomeCrate c) => switch (c) {
  HomeCrate.recent => s.homeCrateRecent,
  HomeCrate.liked => s.crateLiked,
  HomeCrate.suno => s.crateSuno,
  HomeCrate.uploaded => s.crateUploaded,
};

/// 홈의 두 보기입니다. 판 상자를 넘기거나, 책장에 세운 표지를 한눈에 봅니다.
enum HomeView { crate, shelf }

/// 기기마다 마지막으로 고른 보기를 기억하는 키입니다.
const homeViewKey = 'home.view';

/// 판 상자를 위아래로 넘겨 고르는 홈입니다. 맨 앞 판을 누르면 레코드가 빠져나오고,
/// 그 위의 올리기를 누르면 그 분류 전체를 대기열로 올려 그 곡부터 재생합니다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.tracks,
    required this.loading,
    required this.onPlay,
    this.onMenu,
  });

  final Api api;
  final List<Track> tracks;
  final bool loading;
  final void Function(List<Track> list, int index) onPlay;
  final TrackMenuCallback? onMenu;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // 판을 넘기는 위치와 레코드가 빠져나온 정도입니다. 둘 다 끝에서 살짝 넘쳤다 돌아오므로 경계를 두지 않습니다.
  late final AnimationController _pos = AnimationController.unbounded(
    vsync: this,
  )..addListener(_onMove);
  late final AnimationController _pull = AnimationController.unbounded(
    vsync: this,
  );
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 300,
    damping: 26,
  );

  HomeCrate _crate = HomeCrate.recent;
  HomeView _view = HomeView.crate;

  // 저장해 둔 보기를 되살릴 때는 바꾸는 움직임을 보이지 않습니다.
  bool _userSwitched = false;

  /// 기억해 둔 보기를 읽기 전입니다. 그동안은 아무 보기도 그리지 않아 판 상자 자리가 잠깐 떴다가
  /// 격자로 바뀌는 일이 없습니다. 읽는 데는 한 프레임 남짓 걸립니다.
  bool _restoring = true;
  bool _out = false;
  int _front = 0;
  double _dragStart = 0;
  double _dragDy = 0;

  List<Track> get _shown => crateTracks(widget.tracks, _crate);
  bool get _still => MediaQuery.disableAnimationsOf(context);

  /// 왼쪽 메뉴가 보이는 넓은 화면입니다. 거기에 이미 로고가 있어 여기서는 '홈' 제목을 씁니다.
  bool get _wide => MediaQuery.sizeOf(context).width >= 900;

  HomeView get _shownView => _view;

  /// 넓은 화면에서는 판 상자 자리에 표지를 가로로 펼친 주크박스를 씁니다.
  bool get _jukebox => _wide && _view == HomeView.crate;

  /// 처음 곡 목록을 받는 중입니다. 다시 받을 때는 있던 판을 그대로 둡니다.
  bool get _waiting => widget.loading && widget.tracks.isEmpty;

  @override
  void initState() {
    super.initState();
    _restoreView();
  }

  Future<void> _restoreView() async {
    // 기억해 둔 보기를 못 읽으면 판 상자로 시작합니다.
    final saved = await readLocal(homeViewKey);
    final view = HomeView.values.where((v) => v.name == saved).firstOrNull;
    if (view != null && mounted && !_userSwitched) _view = view;
    if (mounted) setState(() => _restoring = false);
  }

  Future<void> _toggleView() async {
    HapticFeedback.selectionClick();
    final next = _view == HomeView.crate ? HomeView.shelf : HomeView.crate;
    _pos.stop();
    _setOut(false);
    setState(() {
      _userSwitched = true;
      _view = next;
    });
    await writeLocal(homeViewKey, next.name);
  }

  void _playFrom(int index) {
    final list = _shown;
    if (index < 0 || index >= list.length) return;
    widget.onPlay(list, index);
  }

  @override
  void didUpdateWidget(HomeScreen old) {
    super.didUpdateWidget(old);
    final n = _shown.length;
    if (_pos.value > n - 1) _pos.value = n == 0 ? 0 : n - 1.0;
  }

  @override
  void dispose() {
    _pos.dispose();
    _pull.dispose();
    super.dispose();
  }

  /// 맨 앞 판이 바뀔 때마다 손끝에 딸깍 하고 알려줍니다.
  void _onMove() {
    final f = frontIndex(_pos.value, _shown.length);
    if (f == _front) return;
    _front = f;
    HapticFeedback.selectionClick();
  }

  void _setOut(bool out) {
    if (out == _out) return;
    setState(() => _out = out);
    if (_still) {
      _pull.value = out ? 1 : 0;
      return;
    }
    _pull.animateTo(
      out ? 1 : 0,
      duration: const Duration(milliseconds: 450),
      curve: discCurve,
    );
  }

  void _pick(HomeCrate c) {
    if (c == _crate) return;
    _pos.stop();
    setState(() => _crate = c);
    _pos.value = 0;
    _front = 0;
    _setOut(false);
  }

  void _tap() {
    if (_shown.isEmpty) return;
    if (!_out) HapticFeedback.mediumImpact();
    _setOut(!_out);
  }

  void _dragStarted(DragStartDetails _) {
    _pos.stop();
    _dragStart = _pos.value;
    _dragDy = 0;
    _setOut(false);
  }

  void _dragged(DragUpdateDetails d) {
    _dragDy += d.delta.dy;
    _pos.value = dragPosition(_dragStart, _dragDy, _shown.length);
  }

  void _dragEnded(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    final target = snapTarget(_pos.value, v, _shown.length).toDouble();
    if (_still) {
      _pos.value = target;
      return;
    }
    _pos.animateWith(
      SpringSimulation(_spring, _pos.value, target, v / flipPixels),
    );
  }

  void _load() {
    final list = _shown;
    if (list.isEmpty) return;
    HapticFeedback.lightImpact();
    widget.onPlay(list, frontIndex(_pos.value, list.length));
    setState(() => _out = false);
    _pull.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final shown = _shown;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: HeaderedBody(
              header: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (_wide)
                          Text(
                            s.tabHome,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Palette.ink,
                              letterSpacing: -.4,
                            ),
                          )
                        else
                          Text.rich(
                            TextSpan(
                              text: 'solo',
                              children: [
                                TextSpan(
                                  text: '.',
                                  style: letterStyle(
                                    30,
                                  ).copyWith(color: Palette.butter),
                                ),
                              ],
                            ),
                            style: letterStyle(30),
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_waiting)
                              const Skeleton(
                                label: false,
                                child: TextBone(
                                  style: TextStyle(fontSize: 12),
                                  width: 34,
                                ),
                              )
                            else
                              AnimatedBuilder(
                                animation: _pos,
                                builder: (_, _) => Text(
                                  shown.isEmpty
                                      ? '0'
                                      : _shownView == HomeView.shelf || _jukebox
                                      ? '${shown.length}'
                                      : '${frontIndex(_pos.value, shown.length) + 1} / ${shown.length}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Palette.faint,
                                    fontFeatures: [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ...[
                              const SizedBox(width: 10),
                              _ViewToggle(
                                view: _view,
                                label: _shownView == HomeView.crate
                                    ? s.homeViewShelf
                                    : s.homeViewCrate,
                                onTap: _toggleView,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        for (final c in HomeCrate.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _Chip(
                              label: _crateName(s, c),
                              on: c == _crate,
                              onTap: () => _pick(c),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              body: AnimatedSwitcher(
                duration: _still || !_userSwitched
                    ? Duration.zero
                    : const Duration(milliseconds: 320),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                // 보기를 바꿀 때는 옛 보기만 옅어지고, 새 보기는 제 등장 동작 하나로만 들어옵니다.
                transitionBuilder: (child, a) =>
                    FadeTransition(opacity: a, child: child),
                child: KeyedSubtree(
                  key: ValueKey((_shownView, _restoring)),
                  child: _restoring
                      ? const SizedBox.expand()
                      : _stage(s, shown),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 곡 목록을 받는 동안은 지금 보기와 같은 모양의 빈 자리를 두고, 받으면 그 위로 판이 들어옵니다.
  Widget _stage(S s, List<Track> shown) => LoadSwitch(
    loading: _waiting,
    skeleton: _shownView == HomeView.shelf
        ? const ShelfSkeleton()
        : Skeleton(
            key: const Key('home-stage-skeleton'),
            child: _fitStage(
              CrateStage(
                api: widget.api,
                tracks: const [],
                position: 0,
                pulled: 0,
                isOut: false,
                hint: '',
                loadLabel: s.homeLoad,
                loadSemantics: s.homeLoadLabel,
                onLoad: () {},
                skeleton: true,
              ),
            ),
          ),
    child: _loaded(s, shown),
  );

  Widget _fitStage(Widget stage) => Align(
    alignment: Alignment.topCenter,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: stage,
    ),
  );

  Widget _loaded(S s, List<Track> shown) {
    final message = widget.tracks.isEmpty
        ? s.homeEmpty
        : shown.isEmpty
        ? s.emptyCrate
        : null;
    if (_shownView == HomeView.shelf) {
      if (message != null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Palette.secondary),
            ),
          ),
        );
      }
      return ShelfGrid(
        key: ValueKey(_crate),
        animateIn: _userSwitched,
        api: widget.api,
        tracks: shown,
        playLabel: s.homeShelfPlay,
        onPlay: _playFrom,
        onMenu: widget.onMenu,
      );
    }
    if (_jukebox) {
      if (message != null) {
        return Center(
          child: Text(
            message,
            style: const TextStyle(fontSize: 14, color: Palette.secondary),
          ),
        );
      }
      return Jukebox(
        key: ValueKey(_crate),
        api: widget.api,
        tracks: shown,
        hint: s.jukeboxHint,
        playLabel: s.homeShelfPlay,
        onPlay: _playFrom,
        onMenu: widget.onMenu,
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        key: const Key('home-stage'),
        behavior: HitTestBehavior.opaque,
        onTap: _tap,
        onVerticalDragStart: _dragStarted,
        onVerticalDragUpdate: _dragged,
        onVerticalDragEnd: _dragEnded,
        child: _fitStage(
          AnimatedBuilder(
            animation: Listenable.merge([_pos, _pull]),
            builder: (_, _) => CrateStage(
              api: widget.api,
              tracks: shown,
              position: _pos.value,
              pulled: _pull.value,
              isOut: _out,
              hint: _out ? s.homeHintOut : s.homeHint,
              loadLabel: s.homeLoad,
              loadSemantics: s.homeLoadLabel,
              onLoad: _load,
              message: message,
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.on, required this.onTap});
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: on,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? Palette.ink : Palette.surface,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: on ? Palette.ink : Palette.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: on ? Palette.ground : Palette.secondary,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 판 상자와 책장 보기를 바꾸는 둥근 단추입니다. 지금 보기가 아닌 쪽의 그림을 보여줍니다.
class _ViewToggle extends StatelessWidget {
  const _ViewToggle({
    required this.view,
    required this.label,
    required this.onTap,
  });

  final HomeView view;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            key: const Key('home-view-toggle'),
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Palette.surface,
                shape: BoxShape.circle,
                border: Border.all(color: Palette.line),
              ),
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: still
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                transitionBuilder: (child, a) => RotationTransition(
                  turns: Tween(begin: -.12, end: 0.0).animate(a),
                  child: ScaleTransition(scale: a, child: child),
                ),
                child: Icon(
                  view == HomeView.crate
                      ? Icons.grid_view_rounded
                      : Icons.layers_rounded,
                  key: ValueKey(view),
                  size: 18,
                  color: Palette.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
