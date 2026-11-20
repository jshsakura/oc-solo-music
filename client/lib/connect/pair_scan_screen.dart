import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import 'server_store.dart';

/// 웹의 연결 탭에 뜬 QR 을 찍어 이 기기를 서버와 짝짓습니다.
class PairScanScreen extends StatefulWidget {
  const PairScanScreen({super.key, required this.onPaired});

  final ValueChanged<Api> onPaired;

  @override
  State<PairScanScreen> createState() => _PairScanScreenState();
}

class _PairScanScreenState extends State<PairScanScreen> {
  final _scanner = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _busy = false;
  String? _note;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _found(BarcodeCapture capture) async {
    if (_busy) return;
    final raw = capture.barcodes.map((b) => b.rawValue).nonNulls.firstOrNull;
    if (raw == null) return;
    final s = S.of(context);
    final link = PairLink.parse(raw);
    if (link == null) {
      setState(() => _note = s.pairBadCode);
      return;
    }
    setState(() {
      _busy = true;
      _note = s.pairConnecting;
    });
    unawaited(HapticFeedback.mediumImpact());
    try {
      final token = await Api.claim(
        link.server,
        link.code,
        name: _deviceName(),
        platform: defaultTargetPlatform.name,
      );
      await ServerStore.save(link.server, token: token);
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onPaired(Api(link.server, token: token));
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _note = s.describe(e);
      });
    }
  }

  String _deviceName() => switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iPhone',
    TargetPlatform.macOS => 'Mac',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    _ => 'Solo',
  };

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      backgroundColor: Palette.ink,
      appBar: AppBar(
        backgroundColor: Palette.ink,
        foregroundColor: Palette.ground,
        title: Text(s.pairScan),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: MobileScanner(
              controller: _scanner,
              onDetect: _found,
              errorBuilder: (context, error) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    s.pairCameraDenied,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Palette.ground),
                  ),
                ),
              ),
            ),
          ),
          const Center(child: _Frame()),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Palette.surface,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                children: [
                  if (_busy)
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Palette.ink,
                      ),
                    )
                  else
                    const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _note ?? s.pairScanHint,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 비출 자리를 알려주는 모서리 네 개입니다.
class _Frame extends StatelessWidget {
  const _Frame();

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 240,
    child: CustomPaint(painter: _CornersPainter()),
  );
}

class _CornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Palette.butter
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const l = 36.0;
    final w = size.width, h = size.height;
    for (final (x, y, dx, dy) in [
      (0.0, 0.0, 1.0, 1.0),
      (w, 0.0, -1.0, 1.0),
      (0.0, h, 1.0, -1.0),
      (w, h, -1.0, -1.0),
    ]) {
      canvas.drawLine(Offset(x, y), Offset(x + l * dx, y), p);
      canvas.drawLine(Offset(x, y), Offset(x, y + l * dy), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
