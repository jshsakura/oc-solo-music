import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets/motion.dart';
import 'widgets/skeleton.dart';
import 'widgets/sleeve.dart';
import 'l10n.dart';

enum Crate { all, liked, suno, uploaded }

String _crateName(S s, Crate c) => switch (c) {
  Crate.all => s.crateAll,
  Crate.liked => s.crateLiked,
  Crate.suno => s.crateSuno,
  Crate.uploaded => s.crateUploaded,
};

bool _inCrate(Track t, Crate c) => switch (c) {
  Crate.all => true,
  Crate.liked => t.liked,
  Crate.suno => t.source == 'suno',
  Crate.uploaded => t.source == 'upload',
};

/// 보관함 목록입니다. 곡을 누르면 그 분류 전체를 대기열로 올리고 그 곡부터 재생합니다.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.api,
    required this.tracks,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onPlay,
    required this.currentId,
    this.playing = false,
  });

  final Api api;
  final List<Track> tracks;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final void Function(List<Track> list, int index) onPlay;
  final String? currentId;

  /// 지금 곡이 돌고 있는지입니다. 돌고 있으면 그 줄의 판이 천천히 돌고 막대가 들썩입니다.
  final bool playing;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Crate _crate = Crate.all;

  /// 줄이 차례로 들어오기 시작한 때입니다. 분류를 바꾸면 다시 셉니다.
  DateTime _shownAt = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final shown = widget.tracks
        .where((t) => _inCrate(t, _crate))
        .toList(growable: false);
    final likes = widget.tracks.where((t) => t.liked).length;
    final waiting = widget.loading && widget.tracks.isEmpty;
    const countStyle = TextStyle(fontSize: 13, color: Palette.faint);
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 2),
            child: Text(
              S.of(context).tabLibrary,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: waiting
                ? const Skeleton(
                    label: false,
                    child: TextBone(style: countStyle, width: 110),
                  )
                : Text(
                    S.of(context).libraryCount(widget.tracks.length, likes),
                    style: countStyle,
                  ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Palette.line)),
            ),
            child: Row(
              children: [
                for (final c in Crate.values)
                  GestureDetector(
                    onTap: () {
                      if (c == _crate) return;
                      HapticFeedback.selectionClick();
                      setState(() {
                        _crate = c;
                        _shownAt = DateTime.now();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      height: 36,
                      margin: const EdgeInsets.only(right: 18),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: c == _crate
                                ? Palette.ink
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _crateName(S.of(context), c),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: c == _crate
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: c == _crate ? Palette.ink : Palette.faint,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: LoadSwitch(
              loading: waiting,
              skeleton: const _ListSkeleton(),
              child: _body(shown),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(List<Track> shown) {
    if (widget.error != null && widget.tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.error!, style: const TextStyle(color: Palette.bad)),
            TextButton(
              onPressed: widget.onRetry,
              child: Text(S.of(context).reload),
            ),
          ],
        ),
      );
    }
    if (shown.isEmpty) {
      return Center(
        child: Text(
          S.of(context).emptyCrate,
          style: const TextStyle(color: Palette.faint),
        ),
      );
    }
    return ListView.separated(
      key: ValueKey(_crate),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: Palette.sunk),
      itemBuilder: (context, i) {
        final t = shown[i];
        final on = t.id == widget.currentId;
        return Appear(
          key: ValueKey(t.id),
          index: i,
          since: _shownAt,
          child: Pressable(
            scale: .97,
            onTap: () {
              HapticFeedback.lightImpact();
              widget.onPlay(shown, i);
            },
            child: SizedBox(
              height: 72,
              child: Row(
                children: [
                  SizedBox(
                    width: 56 + (on ? 26 : 10),
                    height: 56,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutBack,
                          left: on ? 30 : 10,
                          top: 4,
                          child: _PeekDisc(spinning: on && widget.playing),
                        ),
                        Sleeve(track: t, api: widget.api, size: 56, radius: 8),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AnimatedSize(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              child: on
                                  ? Padding(
                                      padding: const EdgeInsets.only(right: 7),
                                      child: EqualizerBars(
                                        playing: widget.playing,
                                        height: 11,
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            Expanded(
                              child: Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: on
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${t.artist} · ${formatTime(t.duration)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Palette.faint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: PopBurst(
                      on: t.liked,
                      reach: 13,
                      child: AnimatedScale(
                        scale: t.liked ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(
                          Icons.favorite_rounded,
                          size: 14,
                          color: Palette.bad,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 곡 목록을 받는 동안의 보관함 줄입니다. 표지 자리와 글 막대 두 줄로, 실제 줄과 높이가 같습니다.
class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  static const _rows = 9;
  static const _titleWidths = [.62, .48, .7, .55, .4, .66, .5, .58, .45];

  @override
  Widget build(BuildContext context) => Skeleton(
    key: const Key('library-skeleton'),
    child: LayoutBuilder(
      builder: (context, box) {
        final text = box.maxWidth - 40 - 66 - 14 - 22;
        return ListView.separated(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          itemCount: _rows,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: Palette.sunk),
          itemBuilder: (_, i) => SizedBox(
            height: 72,
            child: Row(
              children: [
                const SizedBox(
                  width: 66,
                  height: 56,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Bone(width: 56, height: 56, radius: 8),
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextBone(
                      style: const TextStyle(fontSize: 15),
                      width: text * _titleWidths[i],
                    ),
                    TextBone(
                      style: const TextStyle(fontSize: 12),
                      width: text * _titleWidths[i] * .6,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// 지금 곡 표지 뒤로 삐져나온 판입니다. 재생 중이면 홈과 빛줄기가 보이게 천천히 돕니다.
class _PeekDisc extends StatefulWidget {
  const _PeekDisc({required this.spinning});
  final bool spinning;

  @override
  State<_PeekDisc> createState() => _PeekDiscState();
}

class _PeekDiscState extends State<_PeekDisc>
    with SingleTickerProviderStateMixin {
  // 33⅓ rpm 의 절반쯤으로 천천히 돕니다.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  void _sync() {
    final run = widget.spinning && !reducedMotion(context);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_PeekDisc old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: RotationTransition(
      turns: _c,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [Palette.butter, Palette.butter, Palette.ink, Palette.ink],
            stops: [0, .3, .31, 1],
          ),
        ),
        foregroundDecoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              Color(0x00FFFFFF),
              Color(0x38FFFFFF),
              Color(0x00FFFFFF),
              Color(0x00FFFFFF),
              Color(0x22FFFFFF),
              Color(0x00FFFFFF),
            ],
            stops: [0, .08, .18, .5, .58, .68],
          ),
        ),
      ),
    ),
  );
}
