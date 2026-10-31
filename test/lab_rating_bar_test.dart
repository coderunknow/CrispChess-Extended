import 'package:crispchess/widgets/engine_lab/lab_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
