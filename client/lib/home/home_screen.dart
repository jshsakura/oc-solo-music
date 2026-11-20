import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import 'crate_math.dart';
import 'crate_stage.dart';

String _crateName(S s, HomeCrate c) => switch (c) {
  HomeCrate.recent => s.homeCrateRecent,
  HomeCrate.liked => s.crateLiked,
  HomeCrate.suno => s.crateSuno,
  HomeCrate.uploaded => s.crateUploaded,
};

/// 판 상자를 위아래로 넘겨 고르는 홈입니다. 맨 앞 판을 누르면 레코드가 빠져나오고,
/// 그 위의 올리기를 누르면 그 분류 전체를 대기열로 올려 그 곡부터 재생합니다.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.tracks,
    required this.loading,
    required this.onPlay,
  });

  final Api api;
  final List<Track> tracks;
  final bool loading;
  final void Function(List<Track> list, int index) onPlay;

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
  bool _out = false;
  int _front = 0;
  double _dragStart = 0;
  double _dragDy = 0;

  List<Track> get _shown => crateTracks(widget.tracks, _crate);
  bool get _still => MediaQuery.disableAnimationsOf(context);

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
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text.rich(
                  TextSpan(
                    text: 'solo',
                    children: [
                      TextSpan(
                        text: '.',
                        style: letterStyle(30).copyWith(color: Palette.butter),
                      ),
                    ],
                  ),
                  style: letterStyle(30),
                ),
                AnimatedBuilder(
                  animation: _pos,
                  builder: (_, _) => Text(
                    shown.isEmpty
                        ? '0'
                        : '${frontIndex(_pos.value, shown.length) + 1} / ${shown.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Palette.faint,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
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
          Expanded(child: _stage(s, shown)),
        ],
      ),
    );
  }

  Widget _stage(S s, List<Track> shown) {
    if (widget.loading && widget.tracks.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Palette.ink, strokeWidth: 2),
      );
    }
    final message = widget.tracks.isEmpty
        ? s.homeEmpty
        : shown.isEmpty
        ? s.emptyCrate
        : null;
    return GestureDetector(
      key: const Key('home-stage'),
      behavior: HitTestBehavior.opaque,
      onTap: _tap,
      onVerticalDragStart: _dragStarted,
      onVerticalDragUpdate: _dragged,
      onVerticalDragEnd: _dragEnded,
      child: Align(
        alignment: Alignment.topCenter,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topCenter,
          child: AnimatedBuilder(
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
  );
}
