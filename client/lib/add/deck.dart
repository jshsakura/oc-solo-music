import 'dart:math';

import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';

/// 녹음기 데크입니다. 돌고 있는 작업이 있으면 테이프가 들어가 릴이 돌고, 감긴 양이 진행률만큼 옮겨 갑니다.
class Deck extends StatefulWidget {
  const Deck({
    super.key,
    required this.job,
    required this.waiting,
    required this.onCancel,
  });

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
    final p = job?.progress.clamp(0.0, 1.0) ?? 0.0;
    final s = S.of(context);
    final status = job == null
        ? (widget.waiting > 0 ? s.preparingNext : s.idle)
        : s.recordingPct((p * 100).round());
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F16161A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Lamp(on: job != null),
              const SizedBox(width: 8),
              Text(
                status,
                style: const TextStyle(fontSize: 12, color: Palette.secondary),
              ),
              const Spacer(),
              if (widget.waiting > 0)
                Text(
                  s.nextCount(widget.waiting),
                  style: const TextStyle(fontSize: 12, color: Palette.faint),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 112,
            decoration: BoxDecoration(
              color: Palette.ground,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (job == null)
                  Text(
                    s.tapeHint,
                    style: TextStyle(fontSize: 13, color: Palette.faint),
                  ),
                AnimatedSlide(
                  offset: Offset(0, job == null ? -1.4 : 0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    opacity: job == null ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: _Tape(
                      spin: _spin,
                      progress: p,
                      title: job?.label ?? '',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: job == null ? 0 : p,
              minHeight: 4,
              backgroundColor: Palette.sunk,
              color: Palette.butter,
            ),
          ),
          if (job != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                button: true,
                label: s.stopJob,
                child: GestureDetector(
                  onTap: widget.onCancel,
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Palette.ink,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Icon(
                      Icons.eject_rounded,
                      color: Palette.ground,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Lamp extends StatelessWidget {
  const _Lamp({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 250),
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: on ? Palette.bad : Palette.line2,
    ),
  );
}

class _Tape extends StatelessWidget {
  const _Tape({
    required this.spin,
    required this.progress,
    required this.title,
  });

  final Animation<double> spin;
  final double progress;
  final String title;

  @override
  Widget build(BuildContext context) => Container(
    width: 250,
    height: 86,
    decoration: BoxDecoration(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Palette.line),
      boxShadow: const [
        BoxShadow(
          color: Color(0x14161A1A),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: Stack(
      children: [
        // 왼쪽 실패에서 오른쪽 실패로 테이프가 감겨 갑니다.
        _Spool(left: true, radius: 26 - progress * 10),
        _Spool(left: false, radius: 16 + progress * 10),
        Positioned(left: 30, top: 21, child: _Reel(spin: spin)),
        Positioned(right: 30, top: 21, child: _Reel(spin: spin)),
        Positioned(
          left: 50,
          right: 50,
          bottom: 8,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _Spool extends StatelessWidget {
  const _Spool({required this.left, required this.radius});
  final bool left;
  final double radius;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left ? 52 - radius : null,
    right: left ? null : 52 - radius,
    top: 43 - radius,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      width: radius * 2,
      height: radius * 2,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF3A332B),
      ),
    ),
  );
}

class _Reel extends StatelessWidget {
  const _Reel({required this.spin});
  final Animation<double> spin;

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: spin,
    child: CustomPaint(size: const Size(44, 44), painter: const _ReelPainter()),
  );
}

class _ReelPainter extends CustomPainter {
  const _ReelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, 13, Paint()..color = Palette.surface);
    canvas.drawCircle(
      c,
      13,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Palette.ink,
    );
    final spoke = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = Palette.ink;
    for (var i = 0; i < 3; i++) {
      final a = -pi / 2 + i * 2 * pi / 3;
      canvas.drawLine(
        c + Offset(cos(a), sin(a)) * 4,
        c + Offset(cos(a), sin(a)) * 11,
        spoke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
