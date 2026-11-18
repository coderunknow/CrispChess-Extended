import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crispchess/bench/benchmark_settings.dart';

/// Regression tests for the dev6 automatic-benchmark defaults.
///
/// The reported defect: opening the Custom UCI Engines screen silently
/// started a benchmark tournament because both automatic triggers defaulted
/// to ON, and the open-time scan ran before the settings were even read.
void main() {
  test('both automatic triggers default to OFF', () {
    const settings = AutoBenchmarkSettings();
    expect(settings.afterAdd, isFalse,
        reason: 'adding an engine must not start a tournament by default');
    expect(settings.afterVersionChange, isFalse,
        reason: 'opening the manager must not start a tournament by default');
  });

  test('a missing settings document reads as OFF', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = BenchmarkSettingsStore();
    await store.init();
    final settings = await store.autoSettings();
    expect(settings.afterAdd, isFalse);
    expect(settings.afterVersionChange, isFalse);
  });

  test('a stored settings document with missing keys reads as OFF',
      () async {
    // A settings JSON written by an older build that only stored the caps:
    // the triggers are absent, and absence must mean "off", never "on".
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lab.auto': '{"maxGames": 24, "maxDurationMinutes": 10}',
    });
    final store = BenchmarkSettingsStore();
    await store.init();
    final settings = await store.autoSettings();
    expect(settings.afterAdd, isFalse);
    expect(settings.afterVersionChange, isFalse);
    expect(settings.maxGames, 24);
  });

  test('an explicitly enabled setting is preserved', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lab.auto': '{"afterAdd": true, "afterVersionChange": true}',
    });
    final store = BenchmarkSettingsStore();
    await store.init();
    final settings = await store.autoSettings();
    expect(settings.afterAdd, isTrue,
        reason: 'a user who opted in keeps the behaviour');
    expect(settings.afterVersionChange, isTrue);
  });

  test('a corrupt settings document reads as OFF, not ON', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'lab.auto': 'not json at all',
    });
    final store = BenchmarkSettingsStore();
    await store.init();
    final settings = await store.autoSettings();
    expect(settings.afterAdd, isFalse);
    expect(settings.afterVersionChange, isFalse);
  });

  test('round-tripping settings keeps the stored values', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final store = BenchmarkSettingsStore();
    await store.init();
    await store.setAutoSettings(const AutoBenchmarkSettings(
        afterAdd: true, afterVersionChange: false));
    final settings = await store.autoSettings();
    expect(settings.afterAdd, isTrue);
    expect(settings.afterVersionChange, isFalse);
  });

  test('the automatic run config stays capped', () {
    const settings = AutoBenchmarkSettings(
        afterAdd: false, afterVersionChange: false);
    final config = settings.toConfig(seed: 7);
    expect(config.maxGames, lessThanOrEqualTo(24));
    expect(config.maxDuration, lessThanOrEqualTo(const Duration(minutes: 10)));
    expect(config.seed, 7);
  });
}
