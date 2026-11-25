import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solo/api.dart';
import 'package:solo/player/turntable.dart';
import 'package:solo/player_controller.dart';

Track _t(String id) => Track(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  source: 'suno',
  duration: 120,
  hasCover: false,
  liked: false,
);

/// 소리를 내지 않고 대기열만 넘기는 가짜입니다.
class _FakeCtl extends PlayerController {
  _FakeCtl() : super(Api(Uri.parse('http://192.0.2.1:38550'))) {
    queue = [_t('a'), _t('b'), _t('c')];
  }

  @override
  bool get playing => false;

  @override
  void play() {}

  @override
  void pause() {}

  @override
  Future<void> skip(int dir, {bool? play}) async {
    index = (index + dir) % queue.length;
    notifyListeners();
  }
}

Finder get _discs =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_Disc');

Widget _host(_FakeCtl ctl, {required ValueNotifier<bool> shown, Key? key}) =>
    MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: shown,
        builder: (_, on, _) => TickerMode(
          enabled: on,
          child: Center(
            child: Turntable(key: key, ctl: ctl, onHint: (_) {}),
          ),
        ),
      ),
    );

void main() {
  testWidgets('a record changed while the player tab is hidden does not fly '
      'over the other screen', (t) async {
    final ctl = _FakeCtl();
    final shown = ValueNotifier(false);
    await t.pumpWidget(_host(ctl, shown: shown));

    ctl.index = 1;
    ctl.notifyListeners();
    await t.pump(const Duration(milliseconds: 450));
    await t.pump(const Duration(milliseconds: 100));

    expect(_discs, findsOneWidget);
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('leaving the player mid-swap takes the flying record away', (
    t,
  ) async {
    final ctl = _FakeCtl();
    final shown = ValueNotifier(true);
    final deck = GlobalKey<TurntableState>();
    await t.pumpWidget(_host(ctl, shown: shown, key: deck));

    final swapping = deck.currentState!.swap(1);
    await t.pump(const Duration(milliseconds: 450));
    await t.pump(const Duration(milliseconds: 100));
    expect(_discs, findsNWidgets(2), reason: 'the record is in the air');

    shown.value = false;
    await t.pump();
    await t.pump(const Duration(milliseconds: 16));
    expect(_discs, findsOneWidget, reason: 'gone by the next frame');

    await t.pump(const Duration(seconds: 3));
    await swapping;
    expect(ctl.current!.id, 'b');
  });

  Future<void> run(WidgetTester t, int secs) async {
    for (var i = 0; i < secs * 20; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  Future<GlobalKey<TurntableState>> shownDeck(
    WidgetTester t,
    _FakeCtl ctl,
  ) async {
    final deck = GlobalKey<TurntableState>();
    await t.pumpWidget(_host(ctl, shown: ValueNotifier(true), key: deck));
    return deck;
  }

  testWidgets('taps made while the record is leaving skip that many songs', (
    t,
  ) async {
    final ctl = _FakeCtl();
    final deck = await shownDeck(t, ctl);

    final swapping = deck.currentState!.swap(1);
    await t.pump(const Duration(milliseconds: 100));
    unawaited(deck.currentState!.swap(1));
    await run(t, 4);
    await swapping;

    expect(ctl.current!.id, 'c');
  });

  testWidgets('a tap made after the new record arrived swaps once more', (
    t,
  ) async {
    final ctl = _FakeCtl();
    final deck = await shownDeck(t, ctl);

    final swapping = deck.currentState!.swap(1);
    while (ctl.current!.id != 'b') {
      await t.pump(const Duration(milliseconds: 50));
    }
    unawaited(deck.currentState!.swap(1));
    await run(t, 6);
    await swapping;

    expect(ctl.current!.id, 'c');
    expect(_discs, findsOneWidget);
  });

  testWidgets('next then previous during a swap cancel out', (t) async {
    final ctl = _FakeCtl();
    final deck = await shownDeck(t, ctl);

    final swapping = deck.currentState!.swap(1);
    await t.pump(const Duration(milliseconds: 100));
    unawaited(deck.currentState!.swap(-1));
    await run(t, 4);
    await swapping;

    expect(ctl.current!.id, 'a');
  });
}
