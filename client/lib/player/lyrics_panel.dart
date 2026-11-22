import 'package:flutter/material.dart';

import '../l10n.dart';
import '../player_controller.dart';
import '../theme.dart';

/// 재생 화면 아래쪽 남는 자리에 띄우는 가사입니다. 노래가 흘러간 만큼 천천히 따라 내려가고,
/// 손으로 넘기면 잠시 그대로 둡니다. 가사가 없는 곡(연주곡)이면 아무것도 그리지 않습니다.
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({super.key, required this.ctl});

  final PlayerController ctl;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  static final _cache = <String, Future<String>>{};
  final _scroll = ScrollController();
  DateTime _touched = DateTime(0);
  String? _id;

  /// 손으로 넘긴 뒤 이만큼은 따라가기를 멈춥니다.
  static const _hold = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    widget.ctl.addListener(_follow);
  }

  @override
  void didUpdateWidget(LyricsPanel old) {
    super.didUpdateWidget(old);
    if (old.ctl != widget.ctl) {
      old.ctl.removeListener(_follow);
      widget.ctl.addListener(_follow);
    }
  }

  @override
  void dispose() {
    widget.ctl.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  void _follow() {
    if (!_scroll.hasClients) return;
    if (DateTime.now().difference(_touched) < _hold) return;
    final max = _scroll.position.maxScrollExtent;
    final target = (widget.ctl.progress.clamp(0.0, 1.0) * max);
    if ((target - _scroll.offset).abs() < 6) return;
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.ctl.current;
    if (track == null || !track.hasLyrics) return const SizedBox.shrink();
    if (track.id != _id) {
      _id = track.id;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
    final text = _cache.putIfAbsent(
      track.id,
      () => widget.ctl.api.lyrics(track.id),
    );
    return FutureBuilder<String>(
      future: text,
      builder: (context, snap) {
        final lines = (snap.data ?? '').split('\n');
        if ((snap.data ?? '').trim().isEmpty) return const SizedBox.shrink();
        return Container(
          key: const Key('player-lyrics'),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .62),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  S.of(context).lyricsLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Palette.secondary,
                    letterSpacing: .4,
                  ),
                ),
              ),
              Expanded(
                child: NotificationListener<UserScrollNotification>(
                  onNotification: (_) {
                    _touched = DateTime.now();
                    return false;
                  },
                  child: ShaderMask(
                    // 위아래 끝이 부드럽게 사라져 글이 칸에 잘린 것처럼 보이지 않습니다.
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black,
                        Colors.black,
                        Colors.transparent,
                      ],
                      stops: [0, .08, .9, 1],
                    ).createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                      itemCount: lines.length,
                      itemBuilder: (context, i) => _Line(lines[i]),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 가사 한 줄입니다. [Verse] 같은 구간 표시는 작은 라벨로, 빈 줄은 숨 쉬는 틈으로 그립니다.
class _Line extends StatelessWidget {
  const _Line(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = text.trim();
    if (t.isEmpty) return const SizedBox(height: 10);
    final section = RegExp(r'^\[(.+)\]$').firstMatch(t);
    if (section != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Palette.ink,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              section.group(1)!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        t,
        style: const TextStyle(fontSize: 15, height: 1.45, color: Palette.ink),
      ),
    );
  }
}
