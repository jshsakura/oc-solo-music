import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solo/add/deck.dart';
import 'package:solo/api.dart';

void main() {
  final api = Api(Uri.parse('http://192.0.2.1:38550'));

  Future<void> show(WidgetTester tester, Job? job, VoidCallback onCancel) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Deck(api: api, job: job, waiting: 0, onCancel: onCancel),
          ),
        ),
      );

  Job recording({double? duration}) => Job.fromJson({
    'id': 'j1',
    'kind': 'suno',
    'status': 'recording',
    'title': 'Midnight Laundry',
    'progress': 0.62,
    'duration': ?duration,
  });

  testWidgets('shows no stop button while idle', (tester) async {
    await show(tester, null, () {});

    expect(find.bySemanticsLabel('Stop this job'), findsNothing);
    expect(find.text('Add a link and a tape goes in'), findsOneWidget);
  });

  testWidgets('stop button appears while recording and calls onCancel', (
    tester,
  ) async {
    var stopped = 0;
    await show(tester, recording(duration: 201), () => stopped++);

    await tester.tap(find.bySemanticsLabel('Stop this job'));
    await tester.pump();

    expect(stopped, 1);
    expect(find.text('A · Midnight Laundry'), findsOneWidget);
    expect(find.text('Recording 62%'), findsOneWidget);
  });

  testWidgets('shows elapsed and total time only when the length is known', (
    tester,
  ) async {
    await show(tester, recording(duration: 201), () {});
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('2:04 / 3:21'), findsOneWidget);

    await show(tester, recording(), () {});
    expect(find.textContaining(' / '), findsNothing);
  });

  test('reads the song length and ignores a missing or zero one', () {
    expect(Job.fromJson({'id': 'a', 'duration': 201}).duration, 201.0);
    expect(Job.fromJson({'id': 'a', 'duration': 0}).duration, isNull);
    expect(Job.fromJson({'id': 'a'}).duration, isNull);
  });
}
