import 'dart:math';

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/skeleton.dart';

/// 데크만 어두운 기기처럼 그려 밝은 화면에서 눈에 띄게 합니다.
abstract final class _DeckColors {
  static const body = Color(0xFF1C1B1E);
  static const raised = Color(0xFF2A292D);
  static const text = Color(0xFFF2EEE6);
  static const dim = Color(0xFF8E8B86);
  static const rec = Color(0xFFFF5A4E);
  static const recOff = Color(0xFF5A3A37);
  static const bar = Color(0xFFFF6B5E);
  static const track = Color(0xFF3A383B);
  static const shell = Color(0xFFECE8DE);
  static const shellEdge = Color(0xFFD6CFC1);
  static const screw = Color(0xFFCFC7B8);
  static const window = Color(0xFF2B2825);
  static const tape = Color(0xFF5E4B37);
  static const groove = Color(0xFF7A644C);
  static const hub = Color(0xFFF1EDE4);
  static const blade = Color(0xFF1E1B18);
}

/// 녹음기 데크입니다. 돌고 있는 작업이 있으면 카세트의 릴이 돌고, 감긴 테이프가 진행률만큼 옮겨 갑니다.
class Deck extends StatefulWidget {
  const Deck({
    super.key,
    required this.api,
    required this.job,
    required this.waiting,
    required this.onCancel,
  });

  final Api api;
  final Job? job;
  final int waiting;
  final VoidCallback onCancel;

  @override
  State<Deck> createState() => _DeckState();
}

class _DeckState extends State<Deck> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didUpdateWidget(Deck old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final on =
        widget.job != null &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (on && !_spin.isAnimating) _spin.repeat();
    if (!on && _spin.isAnimating) _spin.stop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: _DeckColors.body,
        borderRadius: BorderRadius.circular(26),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2616161A),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Lamp(on: job != null, pulse: _spin),
              const Spacer(),
              if (widget.waiting > 0)
                Text(
                  s.nextCount(widget.waiting),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _DeckColors.dim,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: AnimatedOpacity(
                opacity: job == null ? 0.55 : 1,
                duration: const Duration(milliseconds: 350),
                child: _Cassette(
                  spin: _spin,
                  progress: job?.progress.clamp(0.0, 1.0) ?? 0.0,
                  label: job == null ? s.tapeHint : 'A · ${job.label}',
                  cover: job != null && job.hasCover
                      ? CoverImage(
                          url: widget.api.jobCoverUri(job.id).toString(),
                          headers: widget.api.headers,
                          fallback: const SizedBox.shrink(),
                          placeholder: Bone(
                            radius: 0,
                            color: Palette.ink.withValues(alpha: .12),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          job == null
              ? Text(
                  widget.waiting > 0 ? s.preparingNext : s.idle,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _DeckColors.dim,
                  ),
                )
              : _Meter(job: job, onCancel: widget.onCancel),
        ],
      ),
    );
  }
}

/// 녹음 중 진행률, 지난 시간과 전체 길이, 막대, 멈춤 단추입니다.
class _Meter extends StatelessWidget {
  const _Meter({required this.job, required this.onCancel});

  final Job job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = job.progress.clamp(0.0, 1.0);
    final total = job.duration;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    s.recordingPct((p * 100).round()),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _DeckColors.text,
                    ),
                  ),
                  const Spacer(),
                  // 수노가 곡 길이를 알려 줬을 때만 시간을 보여 줍니다.
                  if (total != null)
                    Text(
                      '${formatTime(p * total)} / ${formatTime(total)}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _DeckColors.dim,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: p),
                  duration: const Duration(milliseconds: 600),
                  builder: (_, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    backgroundColor: _DeckColors.track,
                    color: _DeckColors.bar,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        Semantics(
          button: true,
          label: s.stopJob,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onCancel,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: _DeckColors.raised,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _DeckColors.text,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 녹음 표시등입니다. 녹음하는 동안 밝은 빨강으로 천천히 숨 쉬고, 쉴 때는 어둡게 꺼져 있습니다.
class _Lamp extends StatelessWidget {
  const _Lamp({required this.on, required this.pulse});
  final bool on;
  final AnimationController pulse;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: pulse,
    builder: (context, _) {
      final glow = !on
          ? 0.0
          : pulse.isAnimating
          ? 0.6 + 0.4 * cos(2 * pi * pulse.value)
          : 1.0;
      final lamp = Color.lerp(_DeckColors.recOff, _DeckColors.rec, glow)!;
      return Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lamp,
              boxShadow: [
                if (on)
                  BoxShadow(
                    color: _DeckColors.rec.withValues(alpha: 0.55 * glow),
                    blurRadius: 10,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'REC',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: on ? _DeckColors.text : _DeckColors.dim,
            ),
          ),
        ],
      );
    },
  );
}

/// 크림색 카세트입니다. 위에 노란 라벨, 가운데 어두운 창 속에 릴 두 개, 아래에 사다리꼴 홈이 있습니다.
class _Cassette extends StatelessWidget {
  const _Cassette({
    required this.spin,
    required this.progress,
    required this.label,
    this.cover,
  });

  final Animation<double> spin;
  final double progress;
  final String label;

  /// 라벨 왼쪽 끝에 붙는 곡 표지입니다. 받아 오기 전에는 비어 있습니다.
  final Widget? cover;

  /// 카세트의 가로 대 세로 비율입니다.
  static const aspect = 2.14;

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: aspect,
    child: LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final hub = w * 0.052;
        final labelH = h * 0.15;
        return TweenAnimationBuilder<double>(
          tween: Tween(end: progress),
          duration: const Duration(milliseconds: 600),
          builder: (context, p, _) => Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _ShellPainter(progress: p)),
              ),
              Positioned(
                left: w * 0.045,
                right: w * 0.045,
                top: h * 0.085,
                height: labelH,
                child: _Label(text: label, cover: cover, height: labelH),
              ),
              for (final x in _ShellPainter.reelX)
                Positioned(
                  left: w * x - hub,
                  top: h * _ShellPainter.reelY - hub,
                  child: RotationTransition(
                    turns: spin,
                    child: CustomPaint(
                      size: Size.square(hub * 2),
                      painter: const _HubPainter(),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label({required this.text, required this.cover, required this.height});

  final String text;
  final Widget? cover;
  final double height;

  @override
  Widget build(BuildContext context) {
    final thumb = height - 8;
    return Container(
      decoration: BoxDecoration(
        color: Palette.butter,
        borderRadius: BorderRadius.circular(height * 0.22),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: cover == null
                ? const SizedBox(key: ValueKey(false), width: 8)
                : Padding(
                    key: const ValueKey(true),
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: SizedBox.square(dimension: thumb, child: cover),
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: (height * 0.5).clamp(11.0, 17.0),
                fontWeight: FontWeight.w800,
                color: Palette.ink,
                height: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 카세트 몸통과 창, 감긴 테이프, 아래 홈을 그립니다. 왼쪽 테이프가 진행률만큼 오른쪽으로 옮겨 감깁니다.
class _ShellPainter extends CustomPainter {
  const _ShellPainter({required this.progress});
  final double progress;

  static const reelX = [0.265, 0.735];
  static const reelY = 0.575;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final radius = Radius.circular(w * 0.045);
    // 아래쪽이 조금 더 어두운 테두리라 두께가 있어 보입니다.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = _DeckColors.shellEdge,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h * 0.965), radius),
      Paint()..color = _DeckColors.shell,
    );

    final screw = Paint()..color = _DeckColors.screw;
    for (final (x, y) in [(.022, .05), (.978, .05), (.022, .9), (.978, .9)]) {
      canvas.drawCircle(Offset(w * x, h * y), w * 0.007, screw);
    }

    final window = Rect.fromLTRB(w * 0.16, h * 0.345, w * 0.84, h * 0.805);
    canvas.drawRRect(
      RRect.fromRectAndRadius(window, Radius.circular(window.height / 2)),
      Paint()..color = _DeckColors.window,
    );

    final hub = w * 0.052, room = w * 0.032;
    final spools = [hub + (1 - progress) * room, hub + progress * room];
    for (var i = 0; i < 2; i++) {
      final c = Offset(w * reelX[i], h * reelY);
      final r = spools[i] + w * 0.012;
      canvas.drawCircle(c, r, Paint()..color = _DeckColors.tape);
      final groove = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.8, w * 0.0025)
        ..color = _DeckColors.groove;
      for (var g = hub + w * 0.008; g < r - w * 0.004; g += w * 0.008) {
        canvas.drawCircle(c, g, groove);
      }
    }

    // 아래 가운데의 사다리꼴 홈입니다.
    final notch = Path()
      ..moveTo(w * 0.29, h)
      ..lineTo(w * 0.31, h * 0.905)
      ..quadraticBezierTo(w * 0.312, h * 0.885, w * 0.33, h * 0.885)
      ..lineTo(w * 0.67, h * 0.885)
      ..quadraticBezierTo(w * 0.688, h * 0.885, w * 0.69, h * 0.905)
      ..lineTo(w * 0.71, h)
      ..close();
    canvas.drawPath(notch, Paint()..color = _DeckColors.shellEdge);
  }

  @override
  bool shouldRepaint(_ShellPainter old) => old.progress != progress;
}

/// 릴 가운데의 바람개비 무늬입니다. 돌 때 날개가 눈에 띄게 흑백을 번갈아 둡니다.
class _HubPainter extends CustomPainter {
  const _HubPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(c, r, Paint()..color = _DeckColors.hub);
    final blade = Paint()..color = _DeckColors.blade;
    Offset at(double radius, double angle) =>
        c + Offset(cos(angle), sin(angle)) * radius;
    for (var i = 0; i < 6; i++) {
      final a = i * pi / 3;
      final path = Path()
        ..moveTo(at(r * 0.22, a).dx, at(r * 0.22, a).dy)
        ..lineTo(at(r * 0.9, a + 0.2).dx, at(r * 0.9, a + 0.2).dy)
        ..arcTo(
          Rect.fromCircle(center: c, radius: r * 0.9),
          a + 0.2,
          0.42,
          false,
        )
        ..lineTo(at(r * 0.22, a + 0.42).dx, at(r * 0.22, a + 0.42).dy)
        ..close();
      canvas.drawPath(path, blade);
    }
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.12
        ..color = const Color(0xFF8A7458),
    );
    canvas.drawCircle(c, r * 0.24, blade);
    canvas.drawCircle(c, r * 0.1, Paint()..color = _DeckColors.hub);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
