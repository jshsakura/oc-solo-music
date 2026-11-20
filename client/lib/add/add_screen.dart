import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import 'deck.dart';
import 'jobs_watch.dart';

/// 추가 화면입니다. 주소를 넣으면 대기열에 넣고, 주소가 아닌 글은 유튜브에서 찾아 보여줍니다.
class AddScreen extends StatefulWidget {
  const AddScreen({super.key, required this.api, required this.watch});

  final Api api;
  final JobsWatch watch;

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _sending = false;
  String? _note;
  bool _noteBad = false;
  List<Found> _found = const [];
  final Set<String> _asked = {};

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  static final _url = RegExp(r'^https?://\S+$');

  void _say(String text, {bool bad = false}) => setState(() {
    _note = text;
    _noteBad = bad;
  });

  Future<void> _submit() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final s = S.of(context);
    setState(() => _sending = true);
    try {
      final urls = text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .toList();
      if (urls.every(_url.hasMatch)) {
        final n = await widget.api.add(urls);
        _input.clear();
        setState(() => _found = const []);
        _say(n > 0 ? s.queued(n) : s.alreadyHave);
        await widget.watch.refresh();
      } else {
        final found = await widget.api.search(text);
        setState(() => _found = found);
        _say(found.isEmpty ? s.noneFound : s.foundOnYoutube(found.length));
      }
    } on Exception catch (e) {
      _say(s.describe(e), bad: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _get(Found f) async {
    final s = S.of(context);
    setState(() => _asked.add(f.videoId));
    try {
      final n = await widget.api.get(f);
      _say(n > 0 ? s.getQueued : s.alreadyHave);
      await widget.watch.refresh();
    } on Exception catch (e) {
      setState(() => _asked.remove(f.videoId));
      _say(s.describe(e), bad: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: widget.watch,
        builder: (context, _) {
          final w = widget.watch;
          final history = w.jobs.where((j) => !j.isRunning).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Text(
                S.of(context).tabAdd,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 14),
              _InputRow(
                controller: _input,
                focus: _focus,
                busy: _sending,
                onSubmit: _submit,
              ),
              if (_note != null || w.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
                  child: Text(
                    w.error != null ? S.of(context).describe(w.error!) : _note!,
                    style: TextStyle(
                      fontSize: 12,
                      color: (_noteBad || w.error != null)
                          ? Palette.bad
                          : Palette.faint,
                    ),
                  ),
                ),
              if (_found.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final f in _found)
                  _FoundRow(
                    found: f,
                    asked: _asked.contains(f.videoId),
                    onGet: () => _get(f),
                  ),
              ],
              const SizedBox(height: 16),
              Deck(
                job: w.running,
                waiting: w.waiting,
                onCancel: () => w.running == null ? null : w.cancel(w.running!),
              ),
              if (history.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
                  child: Text(
                    S.of(context).history,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final j in history)
                  _JobRow(job: j, onCancel: () => w.cancel(j)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({
    required this.controller,
    required this.focus,
    required this.busy,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: TextField(
          controller: controller,
          focusNode: focus,
          onSubmitted: (_) => onSubmit(),
          textInputAction: TextInputAction.go,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: S.of(context).inputHint,
            hintStyle: const TextStyle(color: Palette.faint),
            filled: true,
            fillColor: Palette.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 14,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(100),
              borderSide: const BorderSide(color: Palette.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(100),
              borderSide: const BorderSide(color: Palette.ink),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Semantics(
        button: true,
        label: S.of(context).submit,
        child: GestureDetector(
          onTap: onSubmit,
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Palette.butter,
            ),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Palette.ink,
                    ),
                  )
                : const Icon(Icons.add_rounded, size: 26, color: Palette.ink),
          ),
        ),
      ),
    ],
  );
}

class _FoundRow extends StatelessWidget {
  const _FoundRow({
    required this.found,
    required this.asked,
    required this.onGet,
  });

  final Found found;
  final bool asked;
  final VoidCallback onGet;

  @override
  Widget build(BuildContext context) {
    final have = found.owned || asked;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox.square(
              dimension: 44,
              child: found.art.isEmpty
                  ? const ColoredBox(color: Palette.sunk)
                  : Image.network(
                      found.art,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Palette.sunk),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  found.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  [
                    found.artist,
                    if (found.duration > 0) formatTime(found.duration),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Palette.faint),
                ),
              ],
            ),
          ),
          Semantics(
            button: !have,
            label: have ? S.of(context).saved : S.of(context).get,
            child: GestureDetector(
              onTap: have ? null : onGet,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: have ? Palette.sunk : Palette.ink,
                ),
                child: Icon(
                  have ? Icons.check_rounded : Icons.download_rounded,
                  size: 18,
                  color: have ? Palette.good : Palette.ground,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job, required this.onCancel});

  final Job job;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final (icon, color, text) = switch (job.status) {
      'done' => (Icons.check_circle_rounded, Palette.good, s.jobDone),
      'failed' => (
        Icons.error_rounded,
        Palette.bad,
        job.detail.isEmpty ? s.jobFailed : job.detail,
      ),
      'canceled' => (
        Icons.remove_circle_outline_rounded,
        Palette.faint,
        s.jobStopped,
      ),
      _ => (Icons.schedule_rounded, Palette.faint, s.jobWaiting),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.line),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '${job.kind == 'youtube' ? s.youtube : s.suno} · $text',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Palette.faint),
                ),
              ],
            ),
          ),
          if (job.isActive)
            Semantics(
              button: true,
              label: s.removeFromQueue,
              child: GestureDetector(
                onTap: onCancel,
                child: const SizedBox.square(
                  dimension: 40,
                  child: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: Palette.secondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
