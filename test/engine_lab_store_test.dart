import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/services/engine_lab_models.dart';
import 'package:crispchess/services/engine_lab_store.dart';
import 'package:crispchess/services/engine_match_service.dart';

EngineBenchmarkRun sampleRun({String id = 'run-1', String engineName = 'Same name'}) => EngineBenchmarkRun(
      id: id,
      startedAt: DateTime.utc(2026, 10, 31),
      platform: 'linux',
      environment: 'test device',
      config: const EngineBenchmarkConfig(
        preset: EngineBenchmarkPreset.quick,
        gamesPerPairing: 2,
        maxGames: 20,
      ),
      engines: [
        EngineBenchmarkIdentity(id: 'custom:one', name: engineName, version: 'unknown', detectedName: 'Engine 1.0', author: 'Engine author', implementation: 'native'),
        const EngineBenchmarkIdentity(id: 'custom:two', name: 'Same name', version: '1', implementation: 'native'),
      ],
      games: [
        GameResult(
          white: 'Same name', black: 'Same name',
          whiteId: 'custom:one', blackId: 'custom:two', result: '1-0', moves: 22, pgn: '1. e4 e5 1-0',
          whiteMoveMillis: const [10, 20, 30, 40],
          blackMoveMillis: const [5, 6],
        ),
        GameResult(
          white: 'Same name', black: 'Same name',
          whiteId: 'custom:two', blackId: 'custom:one', result: '0-1', moves: 24, pgn: '1. d4 d5 0-1',
        ),
      ],
    );

void main() {
  test('exported engine options redact private paths and credentials', () {
    final description = safeEngineOptionsDescription({
      'Threads': '4',
      'EvalFile': '/home/private/net.onnx',
      'API Token': 'secret-value',
    });
    expect(description, contains('Threads=4'));
    expect(description, isNot(contains('/home/private')));
    expect(description, isNot(contains('secret-value')));
    expect(description, contains('EvalFile=<redacted>'));
  });

  test('configuration workload and validations are deterministic', () {
    const config = EngineBenchmarkConfig(gamesPerPairing: 4, maxGames: 20);
    expect(config.estimatedGames(4), 24);
    expect(config.validate(4), contains(contains('exceeds')));
    expect(config.validate(2), isEmpty);
    expect(const EngineBenchmarkConfig(gamesPerPairing: 3).validate(2), isNotEmpty);
  });

  test('reports round-trip with stable ids, stats and CSV', () {
    final run = sampleRun();
    final decoded = EngineBenchmarkRun.fromJson(jsonDecode(run.toJsonText()) as Map<String, dynamic>);
    expect(decoded.engines.map((e) => e.id), ['custom:one', 'custom:two']);
    expect(decoded.engines.first.author, 'Engine author');
    expect(decoded.engines.first.detectedName, 'Engine 1.0');
    expect(decoded.engines.first.version, 'unknown');
    expect(decoded.ratings, hasLength(2));
    expect(decoded.completedGames, 2);
    expect(EngineBenchmarkRun.toCsv([decoded]), contains('custom:one'));
    expect(decoded.calibratedEloAvailable, isFalse);
    expect(decoded.latencyByEngine['custom:one']?.medianMs, 25);
    expect(decoded.latencyByEngine['custom:one']?.p95Ms, 40);
    expect(decoded.latencyByEngine['custom:one']?.p99Ms, 40);
  });

  test('CSV export neutralizes spreadsheet formulas in user-controlled engine names', () {
    final csv = EngineBenchmarkRun.toCsv([sampleRun(engineName: '=HYPERLINK("https://example.invalid")')]);
    expect(csv, contains("'=HYPERLINK("));
  });

  test('history persists and import never overwrites an existing report', () async {
    String? data;
    String? backup;
    final store = EngineLabStore(
      read: () async => data,
      readBackup: () async => backup,
      write: (value) async { backup = data; data = value; },
    );
    await store.addRun(sampleRun());
    final secondInstance = EngineLabStore(
      read: () async => data,
      readBackup: () async => backup,
      write: (value) async { backup = data; data = value; },
    );
    expect((await secondInstance.load()).single.id, 'run-1');
    await expectLater(secondInstance.importJson(sampleRun().toJsonText()), throwsArgumentError);
    expect((await secondInstance.load()).length, 1);
  });

  test('missing primary history recovers from a validated backup', () async {
    String? written;
    final backup = jsonEncode({'schemaVersion': engineLabSchemaVersion, 'runs': [sampleRun().toJson()]});
    final store = EngineLabStore(
      read: () async => null,
      readBackup: () async => backup,
      write: (value) async { written = value; },
    );
    final runs = await store.load();
    expect(runs.single.id, 'run-1');
    expect(store.recoveredFromBackup, isTrue);
    expect(written, contains('run-1'));
  });

  test('corrupt primary history recovers from validated backup', () async {
    String? written;
    final backup = jsonEncode({'schemaVersion': engineLabSchemaVersion, 'runs': [sampleRun().toJson()]});
    final store = EngineLabStore(
      read: () async => '{not json',
      readBackup: () async => backup,
      write: (value) async { written = value; },
    );
    final runs = await store.load();
    expect(runs.single.id, 'run-1');
    expect(store.recoveredFromBackup, isTrue);
    expect(written, contains('run-1'));
  });
}
