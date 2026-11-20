import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../player_controller.dart';
import '../theme.dart';
import '../l10n.dart';

/// 재생 화면 아래의 알약 막대입니다. 섞기, 반복, 좋아요, 파일 받기, 잠들기 타이머가 들어 있습니다.
class ControlRow extends StatefulWidget {
  const ControlRow({super.key, required this.ctl, required this.onHint});

  final PlayerController ctl;
  final ValueChanged<String> onHint;

  @override
  State<ControlRow> createState() => _ControlRowState();
}

class _ControlRowState extends State<ControlRow> {
  final Set<String> _saved = {};

  PlayerController get _c => widget.ctl;

  Future<void> _download() async {
    final track = _c.current;
    if (track == null) return;
    final ok = await launchUrl(
      _c.api.downloadUri(track.id),
      webOnlyWindowName: '_self',
    );
    if (!mounted) return;
    if (ok) setState(() => _saved.add(track.id));
    widget.onHint(
      ok ? S.of(context).downloadStarted : S.of(context).downloadFailed,
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = _c.current;
    final liked = track?.liked ?? false;
    final saved = track != null && _saved.contains(track.id);
    final s = S.of(context);
    final repeat = _c.repeat;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: [
          _Slot(
            label: _c.shuffle ? s.shuffleOff : s.shuffle,
            active: _c.shuffle,
            icon: Icons.shuffle_rounded,
            onTap: () {
              _c.toggleShuffle();
              widget.onHint(_c.shuffle ? s.shuffleOnHint : s.shuffleOffHint);
            },
          ),
          _Slot(
            label: s.repeatLabels[repeat.index],
            active: repeat != Repeat.off,
            icon: repeat == Repeat.one
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            onTap: () {
              _c.cycleRepeat();
              widget.onHint(s.repeatHints[_c.repeat.index]);
            },
          ),
          _Slot(
            label: s.like,
            active: liked,
            dot: false,
            icon: liked
                ? Icons.favorite_rounded
                : Icons.favorite_border_rounded,
            color: liked ? Palette.bad : null,
            onTap: _c.toggleLike,
          ),
          _Slot(
            label: saved ? s.saved : s.download,
            active: saved,
            dot: false,
            icon: saved ? Icons.check_rounded : Icons.download_rounded,
            color: saved ? Palette.good : null,
            onTap: _download,
          ),
          _Slot(
            label: s.sleepTimer,
            active: _c.sleepMinutes > 0,
            dot: false,
            icon: Icons.bedtime_outlined,
            tag: _c.sleepMinutes > 0 ? s.minutesTag(_c.sleepMinutes) : null,
            onTap: () {
              _c.cycleSleep();
              widget.onHint(
                _c.sleepMinutes > 0 ? s.stopsIn(_c.sleepMinutes) : s.timerOff,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.label,
    required this.active,
    required this.icon,
    required this.onTap,
    this.dot = true,
    this.color,
    this.tag,
  });

  final String label;
  final bool active;
  final IconData icon;
  final VoidCallback onTap;
  final bool dot;
  final Color? color;
  final String? tag;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedScale(
              scale: active ? 1.08 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.elasticOut,
              child: Icon(
                icon,
                size: 22,
                color: color ?? (active ? Palette.ink : Palette.off),
              ),
            ),
            if (dot)
              Positioned(
                bottom: 8,
                child: AnimatedOpacity(
                  opacity: active ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Palette.butter,
                    ),
                  ),
                ),
              ),
            if (tag != null)
              Positioned(
                bottom: 3,
                child: Text(
                  tag!,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
