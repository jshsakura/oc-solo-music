import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solo/widgets/marquee.dart';

Widget _host(String text, double width, {bool reduceMotion = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Center(
          child: SizedBox(
            width: width,
            child: Marquee(text, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ),
    );

double _shiftOf(WidgetTester tester) {
  final t = tester.widgetList<Transform>(find.byType(Transform)).last;
  return -t.transform.getTranslation().x;
}

void main() {
  testWidgets('leaves a title that fits as plain text', (tester) async {
    await tester.pumpWidget(_host('Short', 300));
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('scrolls a long title after a pause and comes back', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host('A very long song title that cannot fit in the slot', 80),
    );
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(_shiftOf(tester), 0);
    await tester.pump(const Duration(seconds: 1));
    expect(_shiftOf(tester), 0);
    await tester.pump(const Duration(seconds: 4));
    expect(_shiftOf(tester), greaterThan(0));
  });

  testWidgets('does not move when the device asks for less motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        'A very long song title that cannot fit in the slot',
        80,
        reduceMotion: true,
      ),
    );
    expect(find.byType(ShaderMask), findsNothing);
  });
}
