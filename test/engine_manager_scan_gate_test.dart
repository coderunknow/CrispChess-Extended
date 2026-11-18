import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crispchess/bench/benchmark_service.dart';
import 'package:crispchess/bench/benchmark_settings.dart';
import 'package:crispchess/bench/benchmark_store.dart';
import 'package:crispchess/bench/benchmark_storage_io.dart';
import 'package:crispchess/screens/engine_manager_screen.dart';

/// Counts how often the Engine Manager's open path asks for changed engines.
///
/// The override does not call the real scan: `testWidgets` runs inside
/// FakeAsync, where real file IO never completes, and the question under
/// test is whether the gate *calls* the scan at all, not what the scan
/// returns.
class RecordingService extends BenchmarkService {
  RecordingService({required super.store});

  int scanCalls = 0;

  @override
  Future<List<ChangedEngine>> changedEngines() async {
    scanCalls++;
    return const [];
  }
}

/// Regression tests for the dev6 open-path gate.
///
/// The defect: opening the Custom UCI Engines screen always ran
/// `changedEngines()` — stat plus, on a cache miss, a full SHA-256 of every
/// previously benchmarked binary — before the settings were consulted, so
/// even a user with automatic benchmarks switched off paid the scan on every
/// visit. After the fix the scan runs only when the after-change trigger can
/// actually start a run.
///
/// The service is built and initialised in `setUp`, which runs outside the
/// FakeAsync zone: the store needs real file IO, which never completes inside
/// a `testWidgets` body.
void main() {
  late Directory temp;
  late RecordingService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temp = await Directory.systemTemp.createTemp('scan-gate-');
    service = RecordingService(
      store: BenchmarkStore(
          storage: FileBenchmarkStorage(rootOverride: temp)),
    );
    await service.init();
  });

  tearDown(() async {
    BenchmarkService.sharedOverride = null;
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  });

  /// Fixed-step pumps, never `pumpAndSettle`: settle waits for the screen's
  /// async chain, and inside FakeAsync a pending real-IO step would never
  /// finish.
  Future<void> openManager(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: EngineManagerScreen()));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 1));
  }

  group('after-change trigger off', () {
    setUp(() async {
      await service.setAutoSettings(const AutoBenchmarkSettings(
        afterAdd: false,
        afterVersionChange: false,
      ));
      BenchmarkService.sharedOverride = service;
    });

    testWidgets('opening the manager does not scan', (tester) async {
      await openManager(tester);

      expect(service.scanCalls, 0,
          reason: 'a disabled re-benchmark trigger must not fingerprint '
              'binaries on open');
    });
  });

  group('after-change trigger on', () {
    setUp(() async {
      await service.setAutoSettings(const AutoBenchmarkSettings(
        afterAdd: false,
        afterVersionChange: true,
      ));
      BenchmarkService.sharedOverride = service;
    });

    testWidgets('opening the manager scans once', (tester) async {
      await openManager(tester);

      expect(service.scanCalls, 1,
          reason: 'the opted-in scan still runs exactly once per visit');
    });
  });

  group('factory settings', () {
    setUp(() {
      // No stored settings document: the constructor defaults decide.
      BenchmarkService.sharedOverride = service;
    });

    testWidgets('opening the manager does not scan', (tester) async {
      await openManager(tester);

      expect(service.scanCalls, 0);
      expect((await service.autoSettings()).afterVersionChange, isFalse);
    });
  });
}
