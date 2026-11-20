import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api.dart';

/// 서버의 작업 목록을 따라갑니다. 돌고 있는 작업이 있으면 자주, 없으면 드물게 물어봅니다.
/// 작업이 새로 끝나면 [onFinished] 를 불러 보관함을 다시 받게 합니다.
class JobsWatch extends ChangeNotifier {
  JobsWatch(this.api, {required this.onFinished});

  final Api api;
  final VoidCallback onFinished;

  static const _busyEvery = Duration(milliseconds: 1500);
  static const _idleEvery = Duration(seconds: 12);

  List<Job> jobs = const [];
  Object? error;
  Timer? _timer;
  bool _disposed = false;
  final Set<String> _seenDone = {};
  bool _primed = false;

  bool get busy => jobs.any((j) => j.isActive);
  Job? get running => jobs.where((j) => j.isRunning).firstOrNull;
  int get waiting => jobs.where((j) => j.status == 'queued').length;

  void start() {
    if (_timer == null) unawaited(refresh());
  }

  Future<void> refresh() async {
    _timer?.cancel();
    try {
      jobs = await api.jobs();
      error = null;
      final done = jobs
          .where((j) => j.status == 'done')
          .map((j) => j.id)
          .toSet();
      final fresh = done.difference(_seenDone);
      _seenDone.addAll(done);
      if (_primed && fresh.isNotEmpty) onFinished();
      _primed = true;
    } on Exception catch (e) {
      error = e;
    }
    if (_disposed) return;
    notifyListeners();
    _timer = Timer(busy ? _busyEvery : _idleEvery, refresh);
  }

  Future<void> cancel(Job job) async {
    try {
      await api.cancel(job.id);
    } on Exception catch (e) {
      error = e;
    }
    await refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
