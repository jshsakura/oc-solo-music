import 'package:flutter/material.dart';

import 'api.dart';
import 'theme.dart';
import 'widgets/sleeve.dart';
import 'l10n.dart';

enum Crate { all, liked, suno, youtube }

String _crateName(S s, Crate c) => switch (c) {
  Crate.all => s.crateAll,
  Crate.liked => s.crateLiked,
  Crate.suno => s.crateSuno,
  Crate.youtube => s.crateYoutube,
};

bool _inCrate(Track t, Crate c) => switch (c) {
  Crate.all => true,
  Crate.liked => t.liked,
  Crate.suno => t.source == 'suno',
  Crate.youtube => t.source == 'youtube',
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
  });

  final Api api;
  final List<Track> tracks;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final void Function(List<Track> list, int index) onPlay;
  final String? currentId;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Crate _crate = Crate.all;

  @override
  Widget build(BuildContext context) {
    final shown = widget.tracks
        .where((t) => _inCrate(t, _crate))
        .toList(growable: false);
    final likes = widget.tracks.where((t) => t.liked).length;
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
            child: Text(
              S.of(context).libraryCount(widget.tracks.length, likes),
              style: const TextStyle(fontSize: 13, color: Palette.faint),
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
                    onTap: () => setState(() => _crate = c),
                    child: Container(
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
          Expanded(child: _body(shown)),
        ],
      ),
    );
  }

  Widget _body(List<Track> shown) {
    if (widget.loading && widget.tracks.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Palette.ink, strokeWidth: 2),
      );
    }
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
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
      itemCount: shown.length,
      separatorBuilder: (_, _) => const Divider(height: 1, color: Palette.sunk),
      itemBuilder: (context, i) {
        final t = shown[i];
        final on = t.id == widget.currentId;
        return InkWell(
          onTap: () => widget.onPlay(shown, i),
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
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                Palette.butter,
                                Palette.butter,
                                Palette.ink,
                                Palette.ink,
                              ],
                              stops: [0, .3, .31, 1],
                            ),
                          ),
                        ),
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
                      Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                        ),
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
                if (t.liked)
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(
                      Icons.favorite_rounded,
                      size: 14,
                      color: Palette.bad,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
