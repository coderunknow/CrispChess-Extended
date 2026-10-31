// The benchmark history: what it promises when things go wrong.
//
// A benchmark is expensive — twenty minutes of a phone's battery — so the
// storage layer is the part where a bug costs the user real work. These tests
// pin the four promises in `benchmark_store.dart`:
//
//   1. a saved run loads back identically;
//   2. a corrupt document is quarantined and named, and the other runs survive;
//   3. a document from a newer schema is refused rather than half-read;
//   4. an import never overwrites an existing run.
import 'dart:convert';

import 'package:crispchess/bench/benchmark_config.dart';
import 'package:crispchess/bench/benchmark_environment.dart';
import 'package:crispchess/bench/benchmark_plan.dart';
import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/bench/benchmark_storage_base.dart';
import 'package:crispchess/bench/benchmark_store.dart';
import 'package:crispchess/bench/calibration.dart';
import 'package:crispchess/bench/elo.dart';
import 'package:crispchess/bench/engine_identity.dart';
import 'package:crispchess/bench/game_record.dart';
import 'package:flutter_test/flutter_test.dart';

final _white = EngineIdentity.forBuiltIn(
    name: 'Built-in', engineVersion: '1.0', appBuild: '2.3.2+18');
final _black = EngineIdentity.forBuiltIn(
    name: 'Lynx', engineVersion: '0.9', appBuild: '2.3.2+18');

BenchGame _game(
  int index, {
  required String whiteId,
  required String blackId,
  required GameOutcome outcome,
  bool warmUp = false,
}) =>
    BenchGame(
      index: index,
      whiteId: whiteId,
      blackId: blackId,
      whiteLabel: whiteId,
      blackLabel: blackId,
      openingId: 'startpos',
      openingName: 'Starting position',
      startFen: '',
      moves: const ['e2e4', 'e7e5'],
      movetext: '1. e4 e5',
      outcome: outcome,
      durationMillis: 1200,
      warmUp: warmUp,
    );

BenchmarkRun _run({
  String id = 'run-a',
  List<BenchGame>? games,
  String stopReason = 'completed',
  CalibrationOutcome? calibration,
}) {
  final played = games ??
      [
        _game(1, whiteId: _white.engineId, blackId: _black.engineId,
            outcome: GameOutcome.whiteWin),
        _game(2, whiteId: _black.engineId, blackId: _white.engineId,
            outcome: GameOutcome.blackWin),
      ];
  return BenchmarkRun(
    id: id,
    startedAt: DateTime.utc(2026, 10, 31, 12),
    finishedAt: DateTime.utc(2026, 10, 31, 12, 20),
    config: BenchmarkConfig.quick,
    format: TournamentFormat.roundRobin,
    engines: [_white, _black],
    engineStatus: {
      _white.engineId: const EngineRunStatus(status: 'completed', gamesCompleted: 2),
      _black.engineId: const EngineRunStatus(status: 'completed', gamesCompleted: 2),
    },
    games: played,
    ratings: fitElo(games: [
      for (final game in played)
        if (game.outcome.isRatingEligible)
          (
            white: game.whiteId,
            black: game.blackId,
            score: game.outcome.whiteScore ?? 0.5
          )
    ], labels: {
      _white.engineId: _white.label,
      _black.engineId: _black.label,
    }),
    calibration: calibration ?? CalibrationOutcome.unavailable('No anchor declared.'),
    environment: BenchmarkEnvironment.unknown,
    stopReason: stopReason,
  );
}

void main() {
  late MemoryBenchmarkStorage storage;
  late BenchmarkStore store;

  setUp(() {
    storage = MemoryBenchmarkStorage();
    store = BenchmarkStore(storage: storage);
  });

  test('a saved run loads back with its games and ratings', () async {
    final run = _run();
    await store.saveRun(run);

    final loaded = await store.loadRun(run.id);
    expect(loaded, isNotNull);
    expect(loaded!.id, run.id);
    expect(loaded.games.length, 2);
    expect(loaded.games.first.outcome, GameOutcome.whiteWin);
    expect(loaded.ratings.ratings.length, 2);
    expect(loaded.config.preset, BenchmarkPreset.quick);
    expect(loaded.stopReason, 'completed');
  });

  test('the index lists runs newest first and survives a reload', () async {
    await store.saveRun(_run(id: 'older'));
    final newer = BenchmarkRun(
      id: 'newer',
      startedAt: DateTime.utc(2026, 10, 31, 13),
      finishedAt: DateTime.utc(2026, 10, 31, 13, 10),
      config: BenchmarkConfig.quick,
      format: TournamentFormat.roundRobin,
      engines: [_white, _black],
      engineStatus: const {},
      games: const [],
      ratings: EloFit.empty,
      calibration: CalibrationOutcome.unavailable('none'),
      environment: BenchmarkEnvironment.unknown,
    );
    await store.saveRun(newer);

    final reopened = BenchmarkStore(storage: storage);
    final summaries = await reopened.summaries();
    expect(summaries.map((s) => s.id).toList(), ['newer', 'older']);
  });

  test('a corrupt document is quarantined by name and does not hide the rest',
      () async {
    await store.saveRun(_run(id: 'good'));
    await storage.write('${kBenchmarkRunPrefix}bad', '{"schema":1,"payl');

    final loaded = await store.loadRun('bad');
    expect(loaded, isNull);

    // The broken document is kept, under a key that says why.
    final quarantined =
        await storage.keys(kBenchmarkCorruptPrefix);
    expect(quarantined, hasLength(1));
    expect(quarantined.single, contains('unreadable'));

    // And the healthy run still loads.
    expect(await store.loadRun('good'), isNotNull);
    expect((await store.summaries()).map((s) => s.id), contains('good'));
  });

  test('a checksum mismatch is treated as corruption, not as a run', () async {
    await store.saveRun(_run(id: 'tampered'));
    final raw = await storage.read('${kBenchmarkRunPrefix}tampered');
    // Change the payload without updating the checksum: exactly what a
    // half-written file or an edited document looks like.
    final document = jsonDecode(raw!) as Map<String, dynamic>;
    (document['payload'] as Map<String, dynamic>)['stopReason'] = 'deleted';
    await storage.write('${kBenchmarkRunPrefix}tampered', jsonEncode(document));

    expect(await store.loadRun('tampered'), isNull);
    expect(await storage.keys(kBenchmarkCorruptPrefix), hasLength(1));
  });

  test('a document from a newer schema is refused, not guessed at', () async {
    final document = jsonDecode(BenchmarkStore.encodeRunDocument(_run()))!
        as Map<String, dynamic>;
    document['schema'] = kBenchmarkStoreSchema + 1;
    await storage.write('${kBenchmarkRunPrefix}future', jsonEncode(document));

    expect(await store.loadRun('future'), isNull);
    // Refused, not quarantined: it is not damaged, this build is old.
    expect(await storage.keys(kBenchmarkCorruptPrefix), isEmpty);
  });

  test('a schema-0 document still loads, with its gaps defaulted', () async {
    final payload = _run(id: 'legacy').toJson()
      ..remove('stopReason')
      ..remove('format')
      ..remove('engineStatus');
    await storage.write(
      '${kBenchmarkRunPrefix}legacy',
      jsonEncode({'schema': 0, 'payload': payload}),
    );

    final loaded = await store.loadRun('legacy');
    expect(loaded, isNotNull);
    expect(loaded!.stopReason, 'completed');
    expect(loaded.format, TournamentFormat.roundRobin);
    expect(loaded.engineStatus, isEmpty);
  });

  test('importing an existing id stores a new run and says the id changed',
      () async {
    final existing = _run(id: 'shared-id');
    await store.saveRun(existing);

    final results = await store.importJson(
      BenchmarkStore.encodeRunDocument(_run(id: 'shared-id')),
    );
    expect(results, hasLength(1));
    expect(results.single.idChanged, isTrue);
    expect(results.single.run.id, isNot('shared-id'));

    // Both runs are kept: an import is not a replacement.
    final ids = (await store.summaries()).map((s) => s.id).toList();
    expect(ids, contains('shared-id'));
    expect(ids, contains(results.single.run.id));
    expect(ids, hasLength(2));
  });

  test('deleting a run removes it from the index and the store', () async {
    await store.saveRun(_run(id: 'gone'));
    expect(await store.deleteRun('gone'), isTrue);
    expect(await store.loadRun('gone'), isNull);
    expect(await store.summaries(), isEmpty);
    // Deleting again is not an error; it is a no-op.
    expect(await store.deleteRun('gone'), isFalse);
  });

  test('saving the same run again replaces it instead of duplicating it',
      () async {
    await store.saveRun(_run(id: 'live', stopReason: 'in progress'));
    await store.saveRun(_run(id: 'live'));
    final summaries = await store.summaries();
    expect(summaries, hasLength(1));
    expect(summaries.single.stopReason, 'completed');
  });

  test('a partial run is stored with its games and marked in progress',
      () async {
    final partial = _run(
      id: 'partial',
      stopReason: 'in progress',
      games: [
        _game(1,
            whiteId: _white.engineId,
            blackId: _black.engineId,
            outcome: GameOutcome.whiteWin),
      ],
    );
    await store.saveRun(partial);
    final loaded = await store.loadRun('partial');
    expect(loaded!.stopReason, 'in progress');
    expect(loaded.games, hasLength(1));
  });

  test('export produces a document that imports back unchanged', () async {
    final run = _run(id: 'roundtrip');
    await store.saveRun(run);
    final exported = await store.exportRunJson('roundtrip');
    expect(exported, isNotNull);

    final other = BenchmarkStore(storage: MemoryBenchmarkStorage());
    final results = await other.importJson(exported!);
    expect(results.single.idChanged, isFalse);
    expect(results.single.run.id, 'roundtrip');
    expect(results.single.run.games.length, 2);
  });

  test('a document that is not a run at all is rejected without a crash',
      () async {
    await expectLater(
      store.importJson('{"schema":1,"payload":{"id":42}}'),
      throwsA(anything),
    );
  });
}
