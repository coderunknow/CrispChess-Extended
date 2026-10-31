import 'package:crispchess/widgets/engine_lab/lab_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('number field retains focus and text through clamped rebuilds', (tester) async {
    var value = 160;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: StatefulBuilder(
      builder: (context, update) => LabNumberField(
        key: const ValueKey('plies'), label: 'Plies', value: value, enabled: true,
        onChanged: (v) => update(() => value = (v ?? 20).clamp(20, 2000)),
      ),
    ))));
    final field = find.byType(TextFormField);
    await tester.tap(field);
    await tester.enterText(field, '1');
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    await tester.enterText(field, '123');
    await tester.pump();
    expect(find.text('123'), findsOneWidget);
    expect(value, 123);
    expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unbounded intervals render without non-finite layout', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: RatingBar(
      label: 'uncertain', rating: 1500,
      ciLow: double.negativeInfinity, ciHigh: double.infinity,
      minRating: double.negativeInfinity, maxRating: double.infinity,
    ))));
    expect(tester.takeException(), isNull);
    expect(find.text('uncertain'), findsOneWidget);
  });
}
