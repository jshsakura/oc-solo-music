import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solo/add/add_screen.dart';
import 'package:solo/add/jobs_watch.dart';
import 'package:solo/api.dart';
import 'package:solo/home/home_screen.dart'; // privacy-ok: 패키지 경로
import 'package:solo/library_screen.dart';
import 'package:solo/widgets/skeleton.dart';

Track _t(String id) => Track(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  source: 'suno',
  duration: 120,
  hasCover: false,
  liked: false,
);

final _tracks = [_t('a'), _t('b')];

/// 작업 목록 답을 시험이 정할 때까지 붙잡아 둡니다.
class _HeldApi extends Api {
  _HeldApi() : super(Uri.parse('http://192.0.2.1:38550'));

  final answer = Completer<List<Job>>();

  @override
  Future<List<Job>> jobs() => answer.future;
}

Widget _app(Widget child, {bool still = false}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: still),
      child: Scaffold(body: child),
    ),
  ),
);

final _shimmer = find.descendant(
  of: find.byType(Skeleton),
  matching: find.byType(ShaderMask),
);

void main() {
  final api = Api(Uri.parse('http://192.0.2.1:38550'));

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget home({required bool loading, List<Track> tracks = const []}) =>
      HomeScreen(api: api, tracks: tracks, loading: loading, onPlay: (_, _) {});

  Widget library({
    required bool loading,
    List<Track> tracks = const [],
    String? error,
  }) => LibraryScreen(
    api: api,
    tracks: tracks,
    loading: loading,
    error: error,
    onRetry: () {},
    onPlay: (_, _) {},
    currentId: null,
  );

  testWidgets('home shows an empty crate while loading, then the records', (
    tester,
  ) async {
    await tester.pumpWidget(_app(home(loading: true)));
    await tester.pump();
    expect(find.byKey(const Key('home-stage-skeleton')), findsOneWidget);
    expect(find.byKey(const Key('home-stage')), findsNothing);
    expect(find.bySemanticsLabel('Loading'), findsWidgets);

    await tester.pumpWidget(_app(home(loading: false, tracks: _tracks)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-stage-skeleton')), findsNothing);
    expect(find.byKey(const Key('home-stage')), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('the shelf view loads with shelf rows of empty covers', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({homeViewKey: 'shelf'});
    await tester.pumpWidget(_app(home(loading: true)));
    await tester.pump();
    expect(find.byKey(const Key('home-shelf-skeleton')), findsOneWidget);

    await tester.pumpWidget(_app(home(loading: false, tracks: _tracks)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home-shelf-skeleton')), findsNothing);
    expect(find.text('Song a'), findsOneWidget);
  });

  testWidgets('library rows are placeholders until the songs arrive', (
    tester,
  ) async {
    await tester.pumpWidget(_app(library(loading: true)));
    await tester.pump();
    expect(find.byKey(const Key('library-skeleton')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(_app(library(loading: false, tracks: _tracks)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-skeleton')), findsNothing);
    expect(find.text('Song a'), findsOneWidget);
    expect(find.text('Song b'), findsOneWidget);
  });

  testWidgets('a failed load shows the error, not an endless skeleton', (
    tester,
  ) async {
    await tester.pumpWidget(_app(library(loading: false, error: 'No server')));
    await tester.pumpAndSettle();
    expect(find.byType(Skeleton), findsNothing);
    expect(find.text('No server'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('add history shows placeholder rows until the first answer', (
    tester,
  ) async {
    final held = _HeldApi();
    final watch = JobsWatch(held, onFinished: () {})..start();
    await tester.pumpWidget(_app(AddScreen(api: held, watch: watch)));
    await tester.pump();
    expect(find.byKey(const Key('history-skeleton')), findsOneWidget);

    held.answer.complete([
      Job.fromJson({'id': 'j1', 'status': 'done', 'title': 'Midnight'}),
    ]);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-skeleton')), findsNothing);
    expect(find.text('Midnight'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    watch.dispose();
  });

  testWidgets('add history skeleton leaves when the first answer fails', (
    tester,
  ) async {
    final held = _HeldApi();
    final watch = JobsWatch(held, onFinished: () {})..start();
    await tester.pumpWidget(_app(AddScreen(api: held, watch: watch)));
    await tester.pump();
    held.answer.completeError(ApiException(ApiFail.jobs));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('history-skeleton')), findsNothing);
    expect(find.text('History'), findsNothing);
    watch.dispose();
  });

  testWidgets('the skeleton shimmers, and stays still with reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(_app(library(loading: true)));
    await tester.pump();
    expect(_shimmer, findsWidgets);

    await tester.pumpWidget(_app(library(loading: true), still: true));
    // 움직이는 것이 없으므로 끝까지 가라앉습니다.
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library-skeleton')), findsOneWidget);
    expect(_shimmer, findsNothing);
    expect(find.byType(Bone), findsWidgets);
  });

  testWidgets('text bones keep the height of the line they stand for', (
    tester,
  ) async {
    const style = TextStyle(fontSize: 22, fontWeight: FontWeight.w700);
    await tester.pumpWidget(
      _app(
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextBone(key: Key('bone'), style: style, width: 120),
            Text('Real title', key: Key('text'), style: style),
          ],
        ),
      ),
    );
    expect(
      tester.getSize(find.byKey(const Key('bone'))).height,
      tester.getSize(find.byKey(const Key('text'))).height,
    );
  });
}
