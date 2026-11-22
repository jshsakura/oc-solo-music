import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:solo/widgets/tab_swap.dart';

class _Counted extends StatefulWidget {
  const _Counted(this.created);
  final List<int> created;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    widget.created.add(1);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  testWidgets('switching tabs keeps the screen instead of building it again', (
    tester,
  ) async {
    final created = <int>[];
    Widget at(bool active) => MaterialApp(
      home: TabSwap(active: active, from: 1, child: _Counted(created)),
    );

    await tester.pumpWidget(at(false));
    await tester.pumpWidget(at(true));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.pumpWidget(at(false));
    await tester.pumpWidget(at(true));
    await tester.pumpAndSettle();

    expect(created, hasLength(1));
  });
}
