import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solo/api.dart';
import 'package:solo/widgets/track_info_sheet.dart'; // privacy-ok: 패키지 경로

const _track = Track(
  id: 'a',
  title: 'Song a',
  artist: 'Artist',
  source: 'suno',
  duration: 125,
  hasCover: false,
  liked: false,
);

class _FakeApi extends Api {
  _FakeApi(this.result) : super(Uri.parse('http://192.0.2.1:38550'));

  final Future<TrackInfo> Function() result;

  @override
  Future<TrackInfo> info(String id) => result();
}

void main() {
  late List<String> clipboard;

  setUp(() {
    clipboard = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
  });

  Future<void> open(WidgetTester t, Api api) async {
    t.view.physicalSize = const Size(420, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) => TextButton(
              onPressed: () => showTrackInfo(c, track: _track, api: api),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  }

  testWidgets('a suno song shows its style and lyrics, each copyable', (
    t,
  ) async {
    await open(
      t,
      _FakeApi(
        () async => const TrackInfo(
          genre: 'dream pop, female vocals',
          lyrics: '[Verse]\nhello',
          duration: 125,
          sunoUrl: 'https://suno.com/song/x',
          sunoModel: 'chirp-v5',
        ),
      ),
    );

    expect(find.text('Style'), findsOneWidget);
    expect(find.text('chirp-v5'), findsOneWidget);
    expect(find.text('2:05'), findsOneWidget);
    expect(find.text('Open in Suno'), findsOneWidget);

    await t.tap(find.text('Copy').first);
    await t.pump();
    await t.tap(find.text('Copy').last);
    await t.pump();
    expect(clipboard, ['dream pop, female vocals', '[Verse]\nhello']);
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets('a song from elsewhere calls it genre and has no suno link', (
    t,
  ) async {
    await open(
      t,
      _FakeApi(() async => const TrackInfo(genre: 'folk', album: 'Home')),
    );

    expect(find.text('Genre'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Open in Suno'), findsNothing);
  });

  testWidgets('a file with no info says so', (t) async {
    await open(t, _FakeApi(() async => const TrackInfo()));
    expect(find.text('This file has no song info'), findsOneWidget);
  });

  testWidgets('a failed request says it could not load', (t) async {
    await open(t, _FakeApi(() => Future.error(ApiException(ApiFail.info))));
    expect(find.textContaining('Could not load song info'), findsOneWidget);
  });
}
