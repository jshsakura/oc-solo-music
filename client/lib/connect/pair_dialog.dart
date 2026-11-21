import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/motion.dart';
import '../widgets/skeleton.dart';

/// 짝짓기 QR 을 띄웁니다. 새 기기가 생기면 알아서 닫히고 true 를 돌려줍니다.
Future<bool> showPairDialog(BuildContext context, Api api) async =>
    await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: reducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: 380),
      pageBuilder: (_, _, _) => _PairDialog(api: api),
      // 작게 웅크렸다가 튀어 오르듯 커지며 뜹니다.
      transitionBuilder: (_, a, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween(begin: .86, end: 1.0).animate(
            CurvedAnimation(
              parent: a,
              curve: Curves.easeOutBack,
              reverseCurve: Curves.easeIn,
            ),
          ),
          child: child,
        ),
      ),
    ) ??
    false;

class _PairDialog extends StatefulWidget {
  const _PairDialog({required this.api});
  final Api api;

  @override
  State<_PairDialog> createState() => _PairDialogState();
}

class _PairDialogState extends State<_PairDialog> {
  static const _checkEvery = Duration(seconds: 2);

  PairOffer? _offer;
  Object? _error;
  Set<String> _known = {};
  String? _paired;
  Timer? _tick;
  Timer? _check;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _check?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _tick?.cancel();
    _check?.cancel();
    setState(() {
      _offer = null;
      _error = null;
    });
    try {
      _known = {for (final d in await widget.api.devices()) d.id};
      final offer = await widget.api.pair();
      if (!mounted) return;
      setState(() => _offer = offer);
      _tick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
      _check = Timer.periodic(_checkEvery, (_) => _lookForNew());
    } on Exception catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _lookForNew() async {
    if (_left <= 0) {
      _check?.cancel();
      return;
    }
    try {
      final fresh = (await widget.api.devices()).where(
        (d) => !_known.contains(d.id),
      );
      if (fresh.isEmpty || !mounted) return;
      _tick?.cancel();
      _check?.cancel();
      unawaited(HapticFeedback.heavyImpact());
      setState(() => _paired = fresh.first.name);
      await Future<void>.delayed(const Duration(milliseconds: 1600));
      if (mounted) Navigator.of(context).pop(true);
    } on Exception {
      // 다음 확인에서 다시 봅니다.
    }
  }

  int get _left {
    final o = _offer;
    if (o == null) return 0;
    return o.expires.difference(DateTime.now()).inSeconds.clamp(0, 9999);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final offer = _offer;
    final expired = offer != null && _left <= 0;
    return Dialog(
      backgroundColor: Palette.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _paired != null ? s.pairDone(_paired!) : s.pairShowTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox.square(
                dimension: 240,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _paired != null
                      ? const _PairedMark(key: ValueKey('done'))
                      : _error != null
                      ? Center(
                          key: const ValueKey('error'),
                          child: Text(
                            s.describe(_error!),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Palette.bad),
                          ),
                        )
                      : offer == null
                      ? const Skeleton(
                          key: ValueKey('wait'),
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Bone(radius: 14),
                          ),
                        )
                      : PulseRings(
                          key: ValueKey(offer.uri),
                          active: !expired,
                          spread: 14,
                          radius: 14,
                          child: AnimatedOpacity(
                            opacity: expired ? 0.15 : 1,
                            duration: const Duration(milliseconds: 300),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: QrImageView(
                                data: offer.uri,
                                padding: EdgeInsets.zero,
                                eyeStyle: const QrEyeStyle(
                                  eyeShape: QrEyeShape.circle,
                                  color: Palette.ink,
                                ),
                                dataModuleStyle: const QrDataModuleStyle(
                                  dataModuleShape: QrDataModuleShape.circle,
                                  color: Palette.ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              if (_paired == null && offer != null)
                Text(
                  expired ? '' : s.pairExpiresIn(_left),
                  style: const TextStyle(fontSize: 12, color: Palette.faint),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (expired || _error != null)
                    TextButton.icon(
                      onPressed: _start,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(s.pairNew),
                      style: TextButton.styleFrom(foregroundColor: Palette.ink),
                    ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      foregroundColor: Palette.secondary,
                    ),
                    child: Text(s.cancel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 짝짓기가 끝나면 체크가 튀어 오르고 둘레로 축하 종이가 터집니다.
class _PairedMark extends StatelessWidget {
  const _PairedMark({super.key});

  @override
  Widget build(BuildContext context) => Stack(
    alignment: Alignment.center,
    clipBehavior: Clip.none,
    children: [
      const Positioned.fill(child: ConfettiBurst()),
      TweenAnimationBuilder<double>(
        tween: Tween(begin: reducedMotion(context) ? 1 : 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.elasticOut,
        builder: (_, v, child) => Transform.scale(scale: v, child: child),
        child: const Icon(
          Icons.check_circle_rounded,
          size: 96,
          color: Palette.good,
        ),
      ),
    ],
  );
}
