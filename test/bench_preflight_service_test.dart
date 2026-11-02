// BenchmarkService.preflight: the service side of Engine Preflight — real
// engines (the built-in Dart engine and user-added UCI scripts), results
// recorded in the gate, engines never omitted, and no preflight while a
// benchmark is being prepared (or the other way round).
@TestOn('vm')
@TestOn('!windows')
library;

import 'dart:async';
import 'dart:io';

import 'package:crispchess/bench/benchmark_service.dart';
import 'package:crispchess/bench/benchmark_storage_base.dart';
import 'package:crispchess/bench/benchmark_store.dart';
import 'package:crispchess/bench/engine_preflight.dart';
import 'package:crispchess/engines/engine_registry.dart';
import 'package:crispchess/engines/generic_uci_engine_stub.dart';
import 'package:crispchess/services/engine_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/bench_harness.dart';

late Directory _dir;

String _script(String name, String body) {
  final file = File('${_dir.path}/$name.sh')
    ..writeAsStringSync('#!/bin/bash\n'
        'while IFS= read -r line; do\n'
        '  case "\$line" in\n'
        '$body\n'
        '  esac\n'
        'done\n');
  Process.runSync('chmod', ['+x', file.path]);
  return file.path;
}

Future<BenchmarkService> _service(List<EngineProfile> profiles) async {
  final store = EngineProfileStore();
  for (final profile in profiles) {
    await store.add(profile);
  }
  return BenchmarkService(
    store: BenchmarkStore(storage: MemoryBenchmarkStorage()),
    profileStore: store,
  );
}

const _fast = EnginePreflight(
  moveTime: Duration(milliseconds: 50),
  searchGrace: Duration(seconds: 10),
  initTimeout: Duration(seconds: 20),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _dir = Directory.systemTemp.createTempSync('crisp_preflight');
  });
  tearDown(() => _dir.deleteSync(recursive: true));

  final builtIn = builtInEngineId('Built-in');

  test('checks real engines, records every result and omits none', () async {
    final broken = EngineProfile(
        id: 'broken', name: 'Broken', path: '${_dir.path}/not-there');
    final service = await _service([broken]);
    final started = <String>[];
    final results = await service.preflight(
      engineIds: [builtIn, 'custom:broken', 'custom:gone'],
      config: benchConfig(),
      consent: (_, __) async => false,
      checker: _fast,
      onEngineStarted: started.add,
    );
    expect(results.map((r) => r.engineId),
        [builtIn, 'custom:broken', 'custom:gone']);
    expect(started, [builtIn, 'custom:broken', 'custom:gone']);
    final byId = {for (final r in results) r.engineId: r};
    expect(byId[builtIn]!.status.admits, isTrue,
        reason: byId[builtIn]!.toDiagnosticText());
    expect(byId['custom:broken']!.status.admits, isFalse);
    expect(byId['custom:gone']!.status, PreflightStatus.unsupported);

    final admission = await service.preflightAdmission(
        [builtIn, 'custom:broken', 'custom:gone'], benchConfig());
    expect(admission.admitted, contains(builtIn));
    expect(admission.excluded.keys,
        containsAll(['custom:broken', 'custom:gone']));
  });

  test('a working UCI script passes; changed settings make it stale',
      () async {
    final path = _script('good', '''
    uci) echo "id name Scripted 1"; echo "option name Hash type spin default 16 min 1 max 64"; echo "uciok" ;;
    isready) echo "readyok" ;;
    go*) echo "bestmove f1c4" ;;
    quit) exit 0 ;;''');
    final service = await _service(
        [EngineProfile(id: 'good', name: 'Good', path: path)]);
    final config = benchConfig();
    final results = await service.preflight(
      engineIds: ['custom:good'],
      config: config,
      consent: (_, __) async => false,
      checker: _fast,
    );
    expect(results.single.status, PreflightStatus.passed,
        reason: results.single.toDiagnosticText());
    expect((await service.preflightAdmission(['custom:good'], config)).admitted,
        ['custom:good']);
    final changed = config.copyWith(hashMb: 32);
    final stale = await service.preflightAdmission(['custom:good'], changed);
    expect(stale.excluded['custom:good'], contains('out of date'));
  });

  test('cancellation reports the remaining engines as not reached', () async {
    final service = await _service(const []);
    final cancellation = PreflightCancellation()..cancel();
    final results = await service.preflight(
      engineIds: [builtIn, builtInEngineId('Frozenight')],
      config: benchConfig(),
      consent: (_, __) async => false,
      checker: _fast,
      cancellation: cancellation,
    );
    expect(results, hasLength(2));
    expect(results.every((r) => r.status == PreflightStatus.cancelled), isTrue);
  });

  test('preflight and benchmark preparation exclude each other', () async {
    final slow = _script('slow', '''
    uci) sleep 1; echo "id name Slow"; echo "uciok" ;;
    isready) echo "readyok" ;;
    go*) echo "bestmove f1c4" ;;
    quit) exit 0 ;;''');
    final service = await _service(
        [EngineProfile(id: 'slow', name: 'Slow', path: slow)]);
    final first = service.preflight(
      engineIds: ['custom:slow'],
      config: benchConfig(),
      consent: (_, __) async => false,
      checker: _fast,
    );
    // Let the first preflight claim the service.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(service.isPreflighting, isTrue);
    await expectLater(
      service.preflight(
        engineIds: [builtIn],
        config: benchConfig(),
        consent: (_, __) async => false,
      ),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.createRunner(engineIds: [builtIn, 'custom:slow'],
          config: benchConfig()),
      throwsA(isA<StateError>()),
    );
    await first;
    expect(service.isPreflighting, isFalse);
  });

  test('a manual run refuses engines the preflight did not admit', () async {
    final service = await _service(const []);
    await expectLater(
      service.createRunner(
        engineIds: [builtIn, builtInEngineId('Frozenight')],
        config: benchConfig(),
        requirePreflight: true,
      ),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', contains('does not admit'))),
    );
    expect(service.isRunning, isFalse);
  });
}
