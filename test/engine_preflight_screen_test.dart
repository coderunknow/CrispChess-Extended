// The Engine Preflight step as the user sees it: one card per engine with its
// status, engines that did not pass listed (never hidden) with the reason,
// diagnostics that can be copied, and no way to continue with fewer than two
// passed engines.
//
// Real engines run here (the built-in Dart engine, and engines that cannot
// start in a test VM), so the checks happen in real time inside runAsync.
@TestOn('vm')
library;

import 'package:crispchess/bench/benchmark_service.dart';
import 'package:crispchess/bench/benchmark_storage_base.dart';
import 'package:crispchess/bench/benchmark_store.dart';
import 'package:crispchess/bench/engine_preflight.dart';
import 'package:crispchess/engines/engine_registry.dart';
import 'package:crispchess/screens/engine_preflight_screen.dart';
import 'package:crispchess/services/engine_profile_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bench_harness.dart';

void main() {
  testWidgets('lists every engine, gates continue on two passed engines',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = BenchmarkService(
      store: BenchmarkStore(storage: MemoryBenchmarkStorage()),
      profileStore: EngineProfileStore(),
    );
    final builtIn = builtInEngineId('Built-in');
    const gone = 'custom:gone';
    final ids = [builtIn, gone];

    await tester.pumpWidget(MaterialApp(
      home: EnginePreflightScreen(
        service: service,
        engineIds: ids,
        labels: {builtIn: 'Built-in', gone: 'Gone engine'},
        config: benchConfig(),
      ),
    ));

    // Let the real checks finish.
    for (var i = 0; i < 150; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      // Advances the test clock as well, for timers created in the test zone.
      await tester.pump(const Duration(milliseconds: 100));
      if (service.preflightGate.results.length == ids.length &&
          !service.isPreflighting) {
        break;
      }
    }
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    final results = service.preflightGate.results;
    expect(results[builtIn]!.status.admits, isTrue,
        reason: results[builtIn]!.toDiagnosticText());
    expect(results[gone]!.status, PreflightStatus.unsupported);

    // Both engines are shown; the one that did not pass is not hidden. Its
    // profile no longer exists, so the card names it the way the rest of the
    // Lab does (engineLabelForId) rather than by a stale caller label.
    expect(find.text('Built-in'), findsWidgets);
    expect(find.text('Removed engine'), findsOneWidget);
    expect(find.text('Not supported here'), findsWidgets);
    expect(find.textContaining('Left out of this run: unsupported'),
        findsOneWidget);
    expect(find.text('Copy diagnostics'), findsNWidgets(2));

    // One passed engine is not a benchmark.
    expect(
        find.text('At least two engines must pass to run a benchmark.'),
        findsOneWidget);
    final continueButton = tester.widget<ButtonStyleButton>(find.ancestor(
        of: find.textContaining('Continue with passed engines'),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    expect(continueButton.onPressed, isNull);
  });
}
