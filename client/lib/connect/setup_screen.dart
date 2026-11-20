import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import 'pair_scan_screen.dart';
import 'server_store.dart';

/// 앱을 처음 열 때 서버 주소를 받습니다. 곡 목록을 한 번 받아 보고 되면 기억합니다.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onConnected});

  final ValueChanged<Api> onConnected;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _address = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _manual = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_busy) return;
    final s = S.of(context);
    final address = ServerStore.parse(_address.text);
    if (address == null) {
      setState(() => _error = s.serverBadAddress);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = Api(address, password: _password.text);
    try {
      await api.tracks();
      await ServerStore.save(address, password: _password.text);
      widget.onConnected(api);
    } on ApiException catch (e) {
      setState(
        () => _error = e.status == 401 ? s.serverWrongPassword : s.describe(e),
      );
    } on Exception catch (e) {
      setState(() => _error = s.describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          children: [
            Text('solo.', style: letterStyle(44)),
            const SizedBox(height: 20),
            Text(
              s.serverTitle,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              s.serverIntro,
              style: const TextStyle(fontSize: 13, color: Palette.secondary),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PairScanScreen(onPaired: widget.onConnected),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: Text(
                  s.pairScan,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.butter,
                  foregroundColor: Palette.ink,
                  shape: const StadiumBorder(),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              s.pairScanHint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Palette.faint),
            ),
            const SizedBox(height: 18),
            Center(
              child: TextButton(
                onPressed: () => setState(() => _manual = !_manual),
                style: TextButton.styleFrom(foregroundColor: Palette.secondary),
                child: Text(s.pairManual),
              ),
            ),
            if (_manual) ...[
              const SizedBox(height: 8),
              _Field(
                controller: _address,
                hint: s.serverAddress,
                keyboard: TextInputType.url,
                onSubmit: _connect,
              ),
              const SizedBox(height: 10),
              _Field(
                controller: _password,
                hint: s.serverPassword,
                obscure: true,
                onSubmit: _connect,
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                  child: Text(
                    _error!,
                    style: const TextStyle(fontSize: 12, color: Palette.bad),
                  ),
                ),
              const SizedBox(height: 14),
              SizedBox(
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _connect,
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.ink,
                    foregroundColor: Palette.ground,
                    shape: const StadiumBorder(),
                  ),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Palette.ground,
                          ),
                        )
                      : Text(
                          s.serverConnect,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.onSubmit,
    this.keyboard,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String hint;
  final VoidCallback onSubmit;
  final TextInputType? keyboard;
  final bool obscure;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboard,
    obscureText: obscure,
    autocorrect: false,
    onSubmitted: (_) => onSubmit(),
    style: const TextStyle(fontSize: 15),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Palette.faint),
      filled: true,
      fillColor: Palette.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(100),
        borderSide: const BorderSide(color: Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(100),
        borderSide: const BorderSide(color: Palette.ink),
      ),
    ),
  );
}
