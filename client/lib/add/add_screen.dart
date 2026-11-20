import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import 'deck.dart';
import 'jobs_watch.dart';

/// 추가 화면입니다. 내가 만든 수노 곡 주소는 녹음 대기열에 넣고, 가진 곡 파일은 바로 올립니다.
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

  /// 올리는 중이면 (끝낸 수, 전체 수) 입니다.
  (int, int)? _uploading;

  static const _audioTypes = [
    'mp3',
    'm4a',
    'flac',
    'wav',
    'ogg',
    'opus',
    'aac',
  ];

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

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
      final n = await widget.api.add(urls);
      _input.clear();
      _say(n > 0 ? s.queued(n) : s.alreadyHave);
      await widget.watch.refresh();
    } on Exception catch (e) {
      _say(s.describe(e), bad: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _upload() async {
    if (_uploading != null) return;
    final s = S.of(context);
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: _audioTypes,
      );
    } on Exception catch (e) {
      _say(s.describe(e), bad: true);
      return;
    }
    if (files.isEmpty || !mounted) return;
    var added = 0, skipped = 0;
    Object? failure;
    for (var i = 0; i < files.length; i++) {
      setState(() => _uploading = (i, files.length));
      try {
        final bytes = await files[i].readAsBytes();
        (await widget.api.upload(files[i].name, bytes)) ? added++ : skipped++;
      } on Exception catch (e) {
        failure = e;
      }
    }
    if (!mounted) return;
    setState(() => _uploading = null);
    if (added > 0) {
      await HapticFeedback.mediumImpact();
      widget.watch.onFinished();
    }
    failure != null && added == 0 && skipped == 0
        ? _say(s.describe(failure), bad: true)
        : _say(s.uploadDone(added, skipped), bad: failure != null);
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
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Text(
                  S.of(context).sunoOwnNote,
                  style: const TextStyle(fontSize: 11.5, color: Palette.faint),
                ),
              ),
              const SizedBox(height: 14),
              _UploadCard(progress: _uploading, onTap: _upload),
              const SizedBox(height: 16),
              Deck(
                api: widget.api,
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

class _UploadCard extends StatelessWidget {
  const _UploadCard({required this.progress, required this.onTap});

  final (int, int)? progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = progress;
    return Semantics(
      button: true,
      label: s.uploadTitle,
      child: Material(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: p == null ? onTap : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Palette.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Palette.butter,
                  ),
                  alignment: Alignment.center,
                  child: p == null
                      ? const Icon(
                          Icons.upload_rounded,
                          size: 24,
                          color: Palette.ink,
                        )
                      : const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Palette.ink,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p == null ? s.uploadTitle : s.uploading(p.$1 + 1, p.$2),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        s.uploadNote,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Palette.faint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
                  '${s.suno} · $text',
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
