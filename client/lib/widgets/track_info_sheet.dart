import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import 'sleeve.dart';

/// 곡 파일에 담긴 정보를 아래에서 올라오는 시트로 보여줍니다.
/// 스타일과 가사는 복사할 수 있어서 같은 결의 곡을 다시 만들 때 그대로 붙여 넣습니다.
Future<void> showTrackInfo(
  BuildContext context, {
  required Track track,
  required Api api,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Palette.surface,
  showDragHandle: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.7,
    maxChildSize: 0.95,
    builder: (_, scroll) => _InfoBody(track: track, api: api, scroll: scroll),
  ),
);

class _InfoBody extends StatefulWidget {
  const _InfoBody({
    required this.track,
    required this.api,
    required this.scroll,
  });

  final Track track;
  final Api api;
  final ScrollController scroll;

  @override
  State<_InfoBody> createState() => _InfoBodyState();
}

class _InfoBodyState extends State<_InfoBody> {
  late final Future<TrackInfo> _info = widget.api.info(widget.track.id);

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(S.of(context).copied)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
      children: [
        _Header(track: widget.track, api: widget.api),
        const SizedBox(height: 16),
        FutureBuilder<TrackInfo>(
          future: _info,
          builder: (context, snap) {
            if (snap.hasError) {
              return _Note(
                snap.error is ApiException
                    ? s.describe(snap.error! as ApiException)
                    : s.apiFail(ApiFail.info),
              );
            }
            final info = snap.data;
            if (info == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _Details(info: info, onCopy: _copy);
          },
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.track, required this.api});

  final Track track;
  final Api api;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Sleeve(track: track, api: api, size: 64, radius: 10),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              track.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (track.artist.isNotEmpty)
              Text(
                track.artist,
                style: const TextStyle(fontSize: 14, color: Palette.secondary),
              ),
          ],
        ),
      ),
    ],
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.info, required this.onCopy});

  final TrackInfo info;
  final void Function(String text) onCopy;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final fromSuno = info.sunoUrl.isNotEmpty;
    final rows = [
      (s.infoAlbum, info.album),
      (s.infoYear, info.year),
      (s.infoLength, info.duration > 0 ? formatTime(info.duration) : ''),
      (s.infoAdded, _day(info.added)),
      (s.infoModel, info.sunoModel),
    ].where((r) => r.$2.isNotEmpty).toList();
    final empty =
        rows.isEmpty && info.genre.isEmpty && info.lyrics.isEmpty && !fromSuno;
    if (empty) return _Note(s.infoNothing);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in rows) _Row(label: label, value: value),
        if (fromSuno)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => launchUrl(Uri.parse(info.sunoUrl)),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(s.infoOpenSuno),
            ),
          ),
        if (info.genre.isNotEmpty)
          _Block(
            label: fromSuno ? s.infoStyle : s.infoGenre,
            text: info.genre,
            onCopy: onCopy,
          ),
        if (info.lyrics.isNotEmpty)
          _Block(label: s.lyricsLabel, text: info.lyrics, onCopy: onCopy),
      ],
    );
  }

  static String _day(int seconds) {
    if (seconds <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(label, style: const TextStyle(color: Palette.faint)),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

/// 제목 줄 오른쪽에 복사 단추가 붙은 긴 글입니다.
class _Block extends StatelessWidget {
  const _Block({required this.label, required this.text, required this.onCopy});

  final String label;
  final String text;
  final void Function(String text) onCopy;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton.icon(
              onPressed: () => onCopy(text),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: Text(S.of(context).copy),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Palette.sunk,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SelectableText(text, style: const TextStyle(height: 1.5)),
        ),
      ],
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: Palette.secondary),
    ),
  );
}
