import 'dart:math';

import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../widgets/artist_tag.dart';
import '../theme.dart';
import 'control_row.dart';
import 'crate_row.dart';
import 'lyrics_panel.dart';
import '../widgets/marquee.dart';
import 'turntable.dart';
import '../l10n.dart';
import '../widgets/motion.dart';
import '../widgets/skeleton.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.ctl, this.loading = false});

  final PlayerController ctl;

  /// 보관함 목록을 받는 중입니다. 아직 올릴 곡이 없으면 제목 자리에 막대를 둡니다.
  final bool loading;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  /// 턴테이블 아래 제목, 진행 막대, 이전·다음 카드가 차지하는 높이의 넉넉한 어림값입니다.
  static const _belowDeck = 240.0;

  final _turntable = GlobalKey<TurntableState>();
  final _stage = GlobalKey();
  String? _hint;

  void _setHint(String text) {
    if (text != _hint) setState(() => _hint = text);
  }

  void _prev() {
    final c = widget.ctl;
    if (c.shownSecs > 3) {
      c.seekSecs(0);
      _setHint(S.of(context).hintRestart);
      return;
    }
    _setHint(S.of(context).hintPrevRecord);
    _turntable.currentState?.swap(-1);
  }

  void _next() {
    _setHint(S.of(context).hintNextRecord);
    _turntable.currentState?.swap(1);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ctl,
      builder: (context, _) {
        final c = widget.ctl;
        final track = c.current;
        final waiting = widget.loading && track == null;
        // 지금 판의 슬리브 색이 위에서 은은하게 번집니다. 판이 바뀌면 천천히 다음 색으로 넘어갑니다.
        final tint = track == null
            ? Palette.ground
            : Palette.sleeveOf(track.id);
        return TweenAnimationBuilder<Color?>(
          key: _stage,
          tween: ColorTween(end: tint),
          duration: reducedMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 900),
          curve: Curves.easeOut,
          builder: (context, glow, child) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  (glow ?? tint).withValues(alpha: .34),
                  (glow ?? tint).withValues(alpha: .10),
                  Palette.ground.withValues(alpha: 0),
                ],
                stops: const [0, .45, .8],
              ),
            ),
            child: child,
          ),
          child: SafeArea(
            bottom: false,
            child: LayoutBuilder(
              builder: (context, box) {
                // 높이가 짧은 기기(가로 화면, 작은 폰)에서는 틈과 표지를 줄이고 턴테이블이 남는 높이에 맞춰 작아집니다.
                final compact = box.maxHeight < 640;
                final gap = compact ? 8.0 : 16.0;
                final titleStyle = TextStyle(
                  fontSize: compact ? 19 : 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: Palette.ink,
                );
                const artistStyle = TextStyle(
                  fontSize: 14,
                  color: Palette.secondary,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          0,
                          compact ? 6 : 12,
                          0,
                          compact ? 8 : 14,
                        ),
                        child: Row(
                          children: [
                            _NowPill(
                              label: S.of(context).nowPlaying,
                              playing: c.playing,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: _HintChip(
                                  text: c.error != null
                                      ? S.of(context).cannotOpen
                                      : (_hint ?? S.of(context).hintStart),
                                  bad: c.error != null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 위쪽 묶음이 남는 높이를 다 받고, 턴테이블은 그 안에서 필요한 만큼만 커집니다.
                      // 키 큰 화면에서 남는 자리는 판 더미와 아래 버튼 막대 사이로 갑니다.
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, inner) {
                            // 턴테이블이 제 크기로 서고도 아래에 가사 칸을 둘 만큼 남으면 그 자리에 가사를 띄웁니다.
                            // 넓은 화면의 재생 칸처럼 키가 큰 곳에서만 해당되고, 폰에서는 턴테이블이 먼저입니다.
                            // 가사를 띄울 때 턴테이블은 키우지 않고 제 크기(또는 폭에 맞춘 크기)로 섭니다.
                            final deckW = min(
                              inner.maxWidth,
                              Turntable.size.width,
                            );
                            final deckH =
                                deckW *
                                Turntable.size.height /
                                Turntable.size.width;
                            final lyrics =
                                (track?.hasLyrics ?? false) &&
                                inner.maxHeight - deckH - _belowDeck > 140;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Flexible(
                                  fit: lyrics ? FlexFit.tight : FlexFit.loose,
                                  flex: lyrics ? 0 : 1,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: Turntable.size.width * 1.2,
                                    ),
                                    child: FittedBox(
                                      child: Turntable(
                                        key: _turntable,
                                        ctl: c,
                                        onHint: _setHint,
                                        stage: _stage,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(height: gap + 4),
                                LoadSwitch(
                                  loading: waiting,
                                  alignment: Alignment.topLeft,
                                  skeleton: _TitleSkeleton(
                                    titleStyle: titleStyle,
                                    artistStyle: artistStyle,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Marquee(
                                        track?.title ?? S.of(context).noTrack,
                                        style: titleStyle,
                                      ),
                                      const SizedBox(height: 6),
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: track == null
                                            ? Text(
                                                S.of(context).pickFromLibrary,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: artistStyle,
                                              )
                                            : ArtistTag(
                                                track.artist,
                                                large: true,
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(height: gap),
                                _SeekBar(ctl: c),
                                SizedBox(height: compact ? 4 : 10),
                                CrateRow(
                                  ctl: c,
                                  onPrev: _prev,
                                  onNext: _next,
                                  edge: 20,
                                  compact: compact,
                                  roomy:
                                      MediaQuery.sizeOf(context).width >= 900,
                                ),
                                if (lyrics) ...[
                                  SizedBox(height: gap),
                                  Expanded(child: LyricsPanel(ctl: c)),
                                ],
                              ],
                            );
                          },
                        ),
                      ),
                      SizedBox(height: gap),
                      ControlRow(ctl: c, onHint: _setHint),
                      SizedBox(height: compact ? 8 : 14),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// 첫 곡이 올라오기 전의 제목과 이름 자리입니다. 같은 글꼴 높이라 곡이 들어와도 아래가 움직이지 않습니다.
class _TitleSkeleton extends StatelessWidget {
  const _TitleSkeleton({required this.titleStyle, required this.artistStyle});

  final TextStyle titleStyle;
  final TextStyle artistStyle;

  @override
  Widget build(BuildContext context) => Skeleton(
    key: const Key('player-skeleton'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextBone(style: titleStyle, width: 190),
        TextBone(style: artistStyle, width: 110),
      ],
    ),
  );
}

class _SeekBar extends StatelessWidget {
  const _SeekBar({required this.ctl});
  final PlayerController ctl;

  void _seekTo(Offset local, double width, {required bool commit}) {
    final secs = (local.dx / width).clamp(0.0, 1.0) * ctl.durationSecs;
    if (commit) {
      ctl.scrubTo(null);
      ctl.seekSecs(secs);
    } else {
      ctl.scrubTo(secs);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _seekTo(d.localPosition, w, commit: true),
          onHorizontalDragUpdate: (d) =>
              _seekTo(d.localPosition, w, commit: false),
          onHorizontalDragEnd: (_) {
            final target = ctl.scrubbing;
            ctl.scrubTo(null);
            if (target != null) ctl.seekSecs(target);
          },
          child: Column(
            children: [
              // 손으로 잡고 있으면 재생 위치 점이 커지고 둘레의 빛이 짙어집니다.
              TweenAnimationBuilder<double>(
                tween: Tween(end: ctl.scrubbing != null ? 1 : 0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                builder: (_, grab, _) => RepaintBoundary(
                  child: CustomPaint(
                    size: const Size.fromHeight(16),
                    painter: _SeekPainter(
                      progress: ctl.progress,
                      grab: grab,
                      playing: ctl.playing,
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Text(
                    formatTime(ctl.shownSecs),
                    style: const TextStyle(fontSize: 12, color: Palette.faint),
                  ),
                  const Spacer(),
                  Text(
                    formatTime(ctl.durationSecs),
                    style: const TextStyle(fontSize: 12, color: Palette.faint),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 재생 막대입니다. 지나온 길은 검게 칠하고, 재생 위치에는 버터색 빛을 두른 점을 찍습니다.
class _SeekPainter extends CustomPainter {
  _SeekPainter({
    required this.progress,
    required this.grab,
    required this.playing,
  });

  final double progress;
  final double grab;
  final bool playing;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final x = size.width * progress.clamp(0.0, 1.0);
    final line = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(2, y),
      Offset(size.width - 2, y),
      line..color = Palette.line,
    );
    if (x > 2) {
      canvas.drawLine(Offset(2, y), Offset(x, y), line..color = Palette.ink);
    }
    final r = 5 + 2.5 * grab;
    final glow = playing || grab > 0 ? 1.0 : .45;
    canvas.drawCircle(
      Offset(x, y),
      r + 5 + 3 * grab,
      Paint()
        ..color = Palette.butter.withValues(alpha: .55 * glow)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(Offset(x, y), r, Paint()..color = Palette.ink);
    canvas.drawCircle(Offset(x, y), r * .42, Paint()..color = Palette.butter);
  }

  @override
  bool shouldRepaint(_SeekPainter old) =>
      old.progress != progress || old.grab != grab || old.playing != playing;
}

/// 지금 재생 표시입니다. 검은 알약 안에서 막대 셋이 소리에 맞춰 춤추고, 멈추면 막대도 눕습니다.
class _NowPill extends StatefulWidget {
  const _NowPill({required this.label, required this.playing});

  final String label;
  final bool playing;

  @override
  State<_NowPill> createState() => _NowPillState();
}

class _NowPillState extends State<_NowPill>
    with SingleTickerProviderStateMixin {
  late final _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(_NowPill old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final calm = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.playing && !calm) {
      if (!_beat.isAnimating) _beat.repeat();
    } else {
      _beat.stop();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
    decoration: BoxDecoration(
      color: Palette.ink,
      borderRadius: BorderRadius.circular(100),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          height: 12,
          child: AnimatedBuilder(
            animation: _beat,
            builder: (context, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final phase in const [0.0, .35, .7])
                  Container(
                    width: 3,
                    height: widget.playing
                        ? 4 +
                              8 *
                                  (.5 +
                                          .5 *
                                              sin(
                                                (_beat.value + phase) * 2 * pi,
                                              ))
                                      .abs()
                        : 3,
                    decoration: BoxDecoration(
                      color: widget.playing ? Palette.butter : Palette.off,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          widget.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Palette.ground,
            letterSpacing: .2,
          ),
        ),
      ],
    ),
  );
}

/// 오른쪽 안내 문구입니다. 반투명 흰 알약에 담고, 바뀔 때 살짝 갈아 끼웁니다.
class _HintChip extends StatelessWidget {
  const _HintChip({required this.text, required this.bad});

  final String text;
  final bool bad;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 220),
    child: Container(
      key: ValueKey(text),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: bad ? const Color(0x1FCC3E34) : const Color(0xB3FFFFFF),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: bad ? const Color(0x40CC3E34) : Palette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            bad ? Icons.error_outline_rounded : Icons.touch_app_outlined,
            size: 13,
            color: bad ? Palette.bad : Palette.faint,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: bad ? Palette.bad : Palette.secondary,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
