import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solo/api.dart';
import 'package:solo/home/crate_math.dart'; // privacy-ok: 패키지 경로
import 'package:solo/home/home_screen.dart'; // privacy-ok: 패키지 경로
import 'package:solo/home/shelf_grid.dart'; // privacy-ok: 패키지 경로

Track _t(String id, {String source = 'suno', bool liked = false}) => Track(
  id: id,
  title: 'Song $id',
  artist: 'Artist',
  source: source,
  duration: 120,
  hasCover: false,
  liked: liked,
);

final _all = [
  _t('a'),
  _t('b', source: 'upload', liked: true),
  _t('c', liked: true),
  _t('d', source: ''),
];

void main() {
  test('each crate keeps only its own records in server order', () {
    List<String> ids(HomeCrate c) => [
      for (final t in crateTracks(_all, c)) t.id,
    ];
    expect(ids(HomeCrate.recent), ['a', 'b', 'c', 'd']);
    expect(ids(HomeCrate.liked), ['b', 'c']);
    expect(ids(HomeCrate.suno), ['a', 'c']);
    expect(ids(HomeCrate.uploaded), ['b']);
  });

  test('dragging moves one record per 120 px and only overshoots a little', () {
    expect(dragPosition(0, 120, 5), 1);
    expect(dragPosition(1, -60, 5), .5);
    expect(dragPosition(0, -500, 5), -0.3);
    expect(dragPosition(4, 500, 5), closeTo(4.3, 1e-9));
    expect(dragPosition(0, 100, 0), 0);
  });

  test(
    'letting go snaps to the nearest record and a fling carries further',
    () {
      expect(snapTarget(1.4, 0, 5), 1);
      expect(snapTarget(1.6, 0, 5), 2);
      expect(snapTarget(1.2, 1200, 5), 3);
      expect(snapTarget(1.2, -1200, 5), 0);
      expect(snapTarget(3.8, 9000, 5), 4);
      expect(snapTarget(-0.3, 0, 5), 0);
      expect(snapTarget(2, 0, 0), 0);
    },
  );

  test('the front record stays inside the crate', () {
    expect(frontIndex(-0.3, 5), 0);
    expect(frontIndex(2.49, 5), 2);
    expect(frontIndex(4.3, 5), 4);
    expect(frontIndex(3, 0), 0);
  });

  test('records behind recede and flipped ones lie forward on top', () {
    final front = sleevePose(0, 2);
    final behind = sleevePose(2, 4);
    final flipped = sleevePose(-1, 1);
    expect(front.tilt, -8);
    expect(behind.dy, lessThan(0));
    expect(behind.dz, lessThan(0));
    expect(flipped.tilt, -78);
    expect(flipped.layer, greaterThan(front.layer));
    expect(sleevePose(-2, 0).opacity, 0);
    expect(sleevePose(7, 9).opacity, 0);
  });

  test('the shelf keeps two columns on a phone and adds more when wider', () {
    expect(shelfColumns(390), 2);
    expect(shelfColumns(320), 2);
    expect(shelfColumns(800), 4);
    expect(shelfColumns(3000), 6);
  });

  group('home screen', () {
    late List<(List<Track>, int)> played;

    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pump(
      WidgetTester tester,
      List<Track> tracks, {
      double width = 390,
    }) async {
      tester.view.physicalSize = Size(width, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      played = [];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeScreen(
              api: Api(Uri.parse('http://192.0.2.1:38550')),
              tracks: tracks,
              loading: false,
              onPlay: (list, i) => played.add((list, i)),
            ),
          ),
        ),
      );
      // 넓은 화면의 주크박스는 레코드가 계속 돌아 멈추기를 기다릴 수 없으니 정해진 시간만 흘려 보냅니다.
      if (width >= 900) {
        await tester.pump(const Duration(seconds: 1));
      } else {
        await tester.pumpAndSettle();
      }
    }

    testWidgets('flips, pulls the record out and loads that record', (
      tester,
    ) async {
      await pump(tester, _all);
      expect(find.text('1 / 4'), findsOneWidget);

      await tester.timedDrag(
        find.byKey(const Key('home-stage')),
        const Offset(0, 130),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 / 4'), findsOneWidget);

      expect(
        find.text('Tap the record to put it on the turntable'),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('home-stage')));
      await tester.pumpAndSettle();
      expect(
        find.text('Tap the record to put it on the turntable'),
        findsOneWidget,
      );

      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();
      expect(played, hasLength(1));
      expect([for (final t in played.single.$1) t.id], ['a', 'b', 'c', 'd']);
      expect(played.single.$2, 1);
    });

    testWidgets('a tap before the record is out pulls it out, not loads it', (
      tester,
    ) async {
      await pump(tester, _all);
      await tester.tap(find.text('Load'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(played, isEmpty);
      expect(
        find.text('Tap the record to put it on the turntable'),
        findsOneWidget,
      );
    });

    testWidgets('a crate chip filters the records and loads from that crate', (
      tester,
    ) async {
      await pump(tester, _all);
      await tester.tap(find.text('Liked'));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-stage')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load'));
      expect([for (final t in played.single.$1) t.id], ['b', 'c']);
      expect(played.single.$2, 0);
    });

    testWidgets('an empty library says so instead of showing records', (
      tester,
    ) async {
      await pump(tester, const []);
      expect(find.text('0'), findsOneWidget);
      expect(find.textContaining('The crate is empty'), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-stage')));
      await tester.pumpAndSettle();
      expect(
        find.text('Tap the record to put it on the turntable'),
        findsNothing,
      );
    });

    testWidgets('the view button swaps the crate for the shelf and back', (
      tester,
    ) async {
      await pump(tester, _all);
      expect(find.byKey(const Key('home-stage')), findsOneWidget);
      expect(find.bySemanticsLabel('Shelf view'), findsOneWidget);

      await tester.tap(find.byKey(const Key('home-view-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-shelf')), findsOneWidget);
      expect(find.byKey(const Key('home-stage')), findsNothing);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Song a'), findsOneWidget);
      expect(find.bySemanticsLabel('Crate view'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(homeViewKey), 'shelf');

      await tester.tap(find.byKey(const Key('home-view-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-stage')), findsOneWidget);
      expect(find.byKey(const Key('home-shelf')), findsNothing);
      expect(prefs.getString(homeViewKey), 'crate');
    });

    testWidgets('the shelf view comes back on the next visit', (tester) async {
      SharedPreferences.setMockInitialValues({homeViewKey: 'shelf'});
      await pump(tester, _all);
      expect(find.byKey(const Key('home-shelf')), findsOneWidget);
    });

    testWidgets('crate chips filter the shelf too', (tester) async {
      // 넓은 화면은 주크박스로 열고, 단추로 격자로 바꿉니다.
      await pump(tester, _all, width: 900);
      expect(find.byKey(const Key('home-jukebox')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-view-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-shelf')), findsOneWidget);

      await tester.tap(find.text('Liked'));
      await tester.pumpAndSettle();
      expect(find.text('Song a'), findsNothing);
      expect(find.text('Song b'), findsOneWidget);
      expect(find.text('Song c'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.text('Uploaded'));
      await tester.pumpAndSettle();
      expect(find.text('Song b'), findsOneWidget);
      expect(find.text('Song c'), findsNothing);
    });

    testWidgets('tapping a cover plays that crate from that record', (
      tester,
    ) async {
      // 넓은 화면은 주크박스로 열고, 단추로 격자로 바꿉니다.
      await pump(tester, _all, width: 900);
      expect(find.byKey(const Key('home-jukebox')), findsOneWidget);
      await tester.tap(find.byKey(const Key('home-view-toggle')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-shelf')), findsOneWidget);
      await tester.tap(find.text('Liked'));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Play Song c'));
      await tester.pumpAndSettle();
      expect(played, hasLength(1));
      expect([for (final t in played.single.$1) t.id], ['b', 'c']);
      expect(played.single.$2, 1);
    });

    testWidgets('an empty crate on the shelf says so', (tester) async {
      await pump(tester, [_t('x', source: 'upload')]);
      await tester.tap(find.byKey(const Key('home-view-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Suno'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home-shelf')), findsNothing);
      expect(find.text('No records here yet'), findsOneWidget);
    });
  });
}
