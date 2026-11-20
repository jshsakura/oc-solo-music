import 'package:flutter/material.dart';

import '../player_controller.dart';
import '../theme.dart';
import 'control_row.dart';
import 'crate_row.dart';
import '../widgets/marquee.dart';
import 'turntable.dart';
import '../l10n.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.ctl});

  final PlayerController ctl;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final _turntable = GlobalKey<TurntableState>();
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
        return SafeArea(
          bottom: false,
          child: LayoutBuilder(
            builder: (context, box) {
              // 높이가 짧은 기기(가로 화면, 작은 폰)에서는 틈과 표지를 줄이고 턴테이블이 남는 높이에 맞춰 작아집니다.
              final compact = box.maxHeight < 640;
              final gap = compact ? 8.0 : 16.0;
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
                          Text(
                            S.of(context).nowPlaying,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: Palette.secondary,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              c.error != null
                                  ? S.of(context).cannotOpen
                                  : (_hint ?? S.of(context).hintStart),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontSize: 12,
                                color: c.error == null
                                    ? Palette.faint
                                    : Palette.bad,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 위쪽 묶음이 남는 높이를 다 받고, 턴테이블은 그 안에서 필요한 만큼만 커집니다.
                    // 키 큰 화면에서 남는 자리는 판 더미와 아래 버튼 막대 사이로 갑니다.
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: Turntable.size.width * 1.2,
                              ),
                              child: FittedBox(
                                child: Turntable(
                                  key: _turntable,
                                  ctl: c,
                                  onHint: _setHint,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: gap + 4),
                          Marquee(
                            track?.title ?? S.of(context).noTrack,
                            style: TextStyle(
                              fontSize: compact ? 19 : 22,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: Palette.ink,
                            ),
                          ),
                          Text(
                            track?.artist ?? S.of(context).pickFromLibrary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Palette.secondary,
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
                          ),
                        ],
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
        );
      },
    );
  }
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
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(100),
                child: LinearProgressIndicator(
                  value: ctl.progress,
                  minHeight: 4,
                  backgroundColor: Palette.line,
                  color: Palette.ink,
                ),
              ),
              const SizedBox(height: 6),
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
