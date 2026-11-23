import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solo/api.dart';
import 'package:solo/library_screen.dart'; // privacy-ok: 패키지 경로
import 'package:solo/widgets/track_menu.dart'; // privacy-ok: 패키지 경로

Track _t(String id, {bool liked = false}) => Track(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  source: 'suno',
  duration: 120,
  hasCover: false,
  liked: liked,
);

/// 서버 대신 부른 기록만 남기는 가짜입니다.
class _FakeApi extends Api {
  _FakeApi() : super(Uri.parse('http://192.0.2.1:38550'));

  final calls = <String>[];

  @override
  Future<void> remove(String id) async => calls.add('remove $id');

  @override
  Future<void> restore(String id) async => calls.add('restore $id');

  @override
  Future<bool> toggleLike(String id) async {
    calls.add('like $id');
    return true;
  }
}

/// 셸이 하는 일을 흉내 냅니다. 메뉴를 열어 고른 동작을 api 로 보내고 목록을 고칩니다.
class _Host extends StatefulWidget {
  const _Host({required this.api, required this.played});
  final _FakeApi api;
  final List<String> played;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  var tracks = [_t('a'), _t('b')];

  Future<void> _menu(Track t, Offset? at) async {
    final a = await showTrackMenu(context, track: t, api: widget.api, at: at);
    if (a == TrackAction.remove) {
      await widget.api.remove(t.id);
      setState(
        () => tracks = [
          for (final x in tracks)
            if (x.id != t.id) x,
        ],
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Removed from the list'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => widget.api.restore(t.id),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: LibraryScreen(
      api: widget.api,
      tracks: tracks,
      loading: false,
      error: null,
      onRetry: () {},
      currentId: null,
      onPlay: (list, i) => widget.played.add(list[i].id),
      onMenu: _menu,
    ),
  );
}

void main() {
  late _FakeApi api;
  late List<String> played;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = _FakeApi();
    played = [];
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: _Host(api: api, played: played),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a tap plays the song and does not open the menu', (t) async {
    await open(t);
    await t.tap(find.text('Song a'));
    await t.pumpAndSettle();
    expect(played, ['a']);
    expect(find.text('Remove from list'), findsNothing);
  });

  testWidgets('a long press opens the sheet with the four actions', (t) async {
    await open(t);
    await t.longPress(find.text('Song a'));
    await t.pumpAndSettle();
    expect(played, isEmpty);
    for (final label in ['Play', 'Like', 'Download', 'Remove from list']) {
      expect(find.text(label), findsOneWidget);
    }
  });

  testWidgets('a liked song offers to unlike', (t) async {
    api = _FakeApi();
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            onPressed: () =>
                showTrackMenu(c, track: _t('z', liked: true), api: api),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Unlike'), findsOneWidget);
    expect(find.text('Like'), findsNothing);
  });

  testWidgets('removing drops the row, then undo restores through the api', (
    t,
  ) async {
    await open(t);
    await t.longPress(find.text('Song a'));
    await t.pumpAndSettle();
    await t.tap(find.text('Remove from list'));
    await t.pumpAndSettle();

    expect(api.calls, ['remove a']);
    expect(find.text('Song a'), findsNothing);
    expect(find.text('Song b'), findsOneWidget);

    await t.tap(find.text('Undo'));
    await t.pumpAndSettle();
    expect(api.calls, ['remove a', 'restore a']);
  });

  testWidgets('a right click opens a popup menu at the pointer', (t) async {
    await open(t);
    final at = t.getCenter(find.text('Song b'));
    final mouse = await t.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.up();
    await t.pumpAndSettle();

    expect(played, isEmpty);
    expect(find.byType(PopupMenuItem<TrackAction>), findsNWidgets(4));
    expect(find.text('Remove from list'), findsOneWidget);
  });
}
