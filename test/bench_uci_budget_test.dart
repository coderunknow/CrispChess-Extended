@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:crispchess/bench/benchmark_environment.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/benchmark_runner.dart';
import 'package:crispchess/engines/generic_uci_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/bench_harness.dart';

void main() {
  test('runner sends nodes and waits for delayed option readiness', () async {
    final dir = Directory.systemTemp.createTempSync('bench_uci_budget');
    addTearDown(() => dir.deleteSync(recursive: true));
    final log = File('${dir.path}/commands');
    final script = File('${dir.path}/engine.sh');
    script.writeAsStringSync('''#!/bin/bash
while IFS= read -r line; do
  echo "\$line" >> '${log.path}'
  case "\$line" in
    uci) echo 'option name Hash type spin default 16 min 1 max 128'; echo uciok ;;
    isready) sleep 0.1; echo ACK >> '${log.path}'; echo readyok ;;
    go*) echo 'bestmove e2e4' ;;
    quit) exit 0 ;;
  esac
done
''');
    Process.runSync('chmod', ['+x', script.path]);
    final identities = [testIdentity('Alpha'), testIdentity('Beta')];
    final config = benchConfig(plyCap: 2).copyWith(
      nodeLimit: () => 1234, hashMb: 32,
    );
    final engines = [
      for (var i = 0; i < 2; i++)
        GenericUciEngine(EngineProfile(name: 'test', path: script.path)),
    ];
    final runner = BenchmarkRunner(
      plan: buildPlan(config: config, engines: identities),
      slots: {
        for (var i = 0; i < 2; i++)
          identities[i].engineId: BenchEngineSlot(
            identity: identities[i], build: () => engines[i]),
      },
      environment: BenchmarkEnvironment.unknown,
    );
    addTearDown(runner.dispose);
    final run = await runner.run();
    final lines = log.readAsLinesSync();
    expect(lines.where((line) => line.startsWith('go ')), isNotEmpty);
    expect(lines.where((line) => line.startsWith('go ')),
        everyElement('go nodes 1234'));
    expect(lines.where((line) => line == 'ACK').length, 4);
    expect(lines.lastIndexOf('ACK'), lessThan(lines.indexOf('go nodes 1234')));
    expect(run.engines.first.configuration['Hash'], '32');
  });

  test('readiness disposal fails instead of acknowledging options', () async {
    final dir = Directory.systemTemp.createTempSync('uci_ready_dispose');
    addTearDown(() => dir.deleteSync(recursive: true));
    final script = File('${dir.path}/engine.sh');
    script.writeAsStringSync('''#!/bin/bash
while IFS= read -r line; do
 case "\$line" in
 uci) echo uciok ;;
 isready) sleep 0.3; echo readyok ;;
 quit) exit 0 ;;
 esac
done
''');
    Process.runSync('chmod', ['+x', script.path]);
    final engine = GenericUciEngine(EngineProfile(name: 'test', path: script.path));
    await engine.initialize();
    final pending = engine.synchronizeOptions();
    final assertion = expectLater(pending, throwsStateError);
    engine.dispose();
    await assertion;
  });
}
