// What happens when a user adds a UCI engine — including when they add a bad
// one.
//
// `initialize()` used to catch every failure, set `EngineState.error` and then
// return normally. The Engine Manager's `try { await initialize() } catch`
// therefore never ran its catch branch, so a wrong path, a binary that is not a
// chess engine, or an engine that never answers `uci` was saved as a working
// profile and only failed on the first move of a game. The handshake timeout
// had the same shape: it logged and carried on to `EngineState.ready`.
//
// These drive the real engine class against small shell scripts, so what is
// asserted is the behaviour of the code that talks to a process, not of a mock.
@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/generic_uci_engine.dart';

late Directory _dir;

/// Writes an executable script that receives every UCI command on stdin.
({String path, String log}) _script(String name, String body) {
  final log = '${_dir.path}/$name.log';
  final file = File('${_dir.path}/$name.sh');
  file.writeAsStringSync('#!/bin/bash\n'
      'while IFS= read -r line; do\n'
      '  echo "\$line" >> "$log"\n'
      '  case "\$line" in\n'
      '$body\n'
      '  esac\n'
      'done\n');
  Process.runSync('chmod', ['+x', file.path]);
  return (path: file.path, log: log);
}

/// A well-behaved engine that also reports an `info` line before its move.
({String path, String log}) _workingEngine({
  String idName = 'TestEngine 1.0',
  bool advertisesSkillLevel = false,
}) =>
    _script('working', '''
    uci)
      echo "id name $idName"
      echo "id author Test Suite"
      echo "option name Hash type spin default 16 min 1 max 1024"
      echo "option name Threads type spin default 1 min 1 max 8"
      echo "option name Style type combo default Normal var Normal var Aggressive"
      echo "option name Clear Hash type button"
      ${advertisesSkillLevel ? 'echo "option name Skill Level type spin default 20 min 0 max 20"' : ''}
      echo "uciok"
      ;;
    isready) echo "readyok" ;;
    go*)
      sleep 0.1
      echo "info depth 3 seldepth 5 multipv 1 score cp 100 pv e2e4 e7e5"
      echo "bestmove e2e4"
      ;;
''');

List<String> _logLines(String path) =>
    File(path).existsSync() ? File(path).readAsLinesSync() : const [];

/// The child process writes its log as it reads; give it a moment rather than
/// asserting on a file it may not have flushed yet.
Future<List<String>> _logLinesWhen(
  String path,
  bool Function(List<String> lines) predicate,
) async {
  for (var i = 0; i < 40; i++) {
    final lines = _logLines(path);
    if (predicate(lines)) return lines;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return _logLines(path);
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('crispchess_init'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('a profile that cannot work is not reported as working', () {
    test('a missing binary throws and leaves the engine in error', () async {
      final engine = GenericUciEngine(EngineProfile(
        name: 'Ghost',
        path: '${_dir.path}/does-not-exist',
      ));

      await expectLater(engine.initialize(), throwsA(isA<FileSystemException>()));
      expect(engine.state, EngineState.error);
      engine.dispose();
    });

    test('a binary that is not executable throws', () async {
      final file = File('${_dir.path}/not-executable')..writeAsStringSync('hi');
      final engine = GenericUciEngine(
          EngineProfile(name: 'NotExec', path: file.path));

      await expectLater(engine.initialize(), throwsA(isA<ProcessException>()));
      expect(engine.state, EngineState.error);
      engine.dispose();
    });

    test('an engine that never answers `uci` times out and is not ready',
        () async {
      // Speaks nothing, stays alive: the "it is running but it is not a chess
      // engine" case.
      final fake = _script('mute', 'uci) sleep 30 ;; quit) exit 0 ;;');
      final engine = GenericUciEngine(
        EngineProfile(name: 'Mute', path: fake.path),
        handshakeTimeout: const Duration(milliseconds: 300),
      );

      await expectLater(
          engine.initialize(), throwsA(isA<TimeoutException>()));
      expect(engine.state, EngineState.error,
          reason: 'a silent engine must never be reported as ready');
      engine.dispose();
    });

    test('an engine that dies during the handshake reports the death', () async {
      final fake = _script('dies', 'uci) echo "id name Dying"; exit 4 ;;');
      final engine = GenericUciEngine(EngineProfile(name: 'Dying', path: fake.path));

      await expectLater(
          engine.initialize(), throwsA(isA<EngineProcessDiedException>()));
      expect(engine.state, EngineState.error);
      engine.dispose();
    });
  });

  group('a working engine', () {
    test('reaches ready and reports the identity it detected', () async {
      final fake = _workingEngine();
      final engine = GenericUciEngine(
        // No user-supplied name: the engine's own name is used.
        EngineProfile(name: '', path: fake.path),
      );
      await engine.initialize();
      addTearDown(engine.dispose);

      expect(engine.state, EngineState.ready);
      expect(engine.name, 'TestEngine 1.0');
      expect(engine.engineIdentifier, 'TestEngine 1.0');
      expect(engine.engineAuthor, 'Test Suite');
      expect(engine.profile.detectedName, 'TestEngine 1.0');
    });

    test('a user-supplied name is kept, with the identity alongside', () async {
      final fake = _workingEngine();
      final engine = GenericUciEngine(
        EngineProfile(name: 'My Strong Engine', path: fake.path),
      );
      await engine.initialize();
      addTearDown(engine.dispose);

      expect(engine.name, 'My Strong Engine');
      expect(engine.engineIdentifier, 'TestEngine 1.0');
    });

    test('discovers the engine options', () async {
      final fake = _workingEngine();
      final engine = GenericUciEngine(
          EngineProfile(name: 'Opts', path: fake.path));
      await engine.initialize();
      addTearDown(engine.dispose);

      final names = engine.options.map((o) => o.name).toList();
      expect(names, ['Hash', 'Threads', 'Style', 'Clear Hash']);
      expect(engine.profile.optionCount, 4);

      final hash = engine.options.firstWhere((o) => o.name == 'Hash');
      expect(hash.min, 1);
      expect(hash.max, 1024);
      expect(hash.defaultValue, '16');

      final style = engine.options.firstWhere((o) => o.name == 'Style');
      expect(style.comboValues, ['Normal', 'Aggressive']);
    });

    test('saved option overrides are sent before the first search', () async {
      final fake = _workingEngine();
      final engine = GenericUciEngine(EngineProfile(
        name: 'Opts',
        path: fake.path,
        optionOverrides: {'Hash': '256', 'Threads': '4'},
      ));
      await engine.initialize();
      addTearDown(engine.dispose);

      final sent = await _logLinesWhen(
        fake.log,
        (lines) => lines.contains('setoption name Threads value 4'),
      );
      expect(sent, contains('setoption name Hash value 256'));
      expect(sent, contains('setoption name Threads value 4'));
    });

    test('the application strength level never overwrites profile Skill Level', () async {
      final fake = _workingEngine(advertisesSkillLevel: true);
      final engine = GenericUciEngine(EngineProfile(
        name: 'Skill test',
        path: fake.path,
        optionOverrides: {'Skill Level': '7'},
      ));
      await engine.initialize();
      addTearDown(engine.dispose);

      await engine.bestMove('position startpos', skillLevel: 2);
      final sent = _logLines(fake.log);
      expect(sent, contains('setoption name Skill Level value 7'));
      expect(sent, isNot(contains('setoption name Skill Level value 2')));
    });

    test('initialising twice does not duplicate the option list', () async {
      // The options list is a field, and the handshake appends to it: a second
      // handshake on the same instance (which EngineSlot could trigger) would
      // list every option twice.
      final fake = _workingEngine();
      final engine = GenericUciEngine(
          EngineProfile(name: 'Opts', path: fake.path));
      await engine.initialize();
      addTearDown(engine.dispose);
      expect(engine.options, hasLength(4));

      await engine.initialize();
      expect(engine.options, hasLength(4));
    });
  });

  group('evaluation perspective', () {
    // `score cp` is from the side to move. EvalInfo is from White's. Reading
    // the number unchanged inverted the eval bar on every Black-to-move
    // position — and the analysis panel, and the chart.
    Future<double> firstScore(String positionCommand) async {
      final fake = _workingEngine();
      final engine =
          GenericUciEngine(EngineProfile(name: 'Eval', path: fake.path));
      await engine.initialize();
      addTearDown(engine.dispose);

      final info = await engine
          .analyze(positionCommand, depth: 3)
          .first
          .timeout(const Duration(seconds: 5));
      engine.stop();
      return info.score;
    }

    test('White to move: +1.00 for White is +1.00', () async {
      expect(await firstScore('position startpos'), closeTo(1.0, 1e-9));
    });

    test('Black to move: +1.00 for Black is -1.00 for White', () async {
      // 1.e4 leaves Black to move; the engine's +1.00 is Black's.
      expect(
        await firstScore('position startpos moves e2e4'),
        closeTo(-1.0, 1e-9),
      );
    });

    test('a mate score is flipped the same way', () async {
      Future<double> mateScore(String positionCommand) async {
        final fake = _script('mate', '''
        uci) echo "id name Matey"; echo "uciok" ;;
        isready) echo "readyok" ;;
        go*)
          sleep 0.1
          echo "info depth 5 score mate 3 pv e2e4 e7e5"
          echo "bestmove e2e4"
          ;;
''');
        final engine = GenericUciEngine(
            EngineProfile(name: 'Matey', path: fake.path));
        await engine.initialize();
        addTearDown(engine.dispose);
        final info = await engine
            .analyze(positionCommand, depth: 5)
            .first
            .timeout(const Duration(seconds: 5));
        return info.score;
      }

      // Mate for the side to move, so White's mate is positive and Black's is
      // negative once converted.
      expect(await mateScore('position startpos'), greaterThan(0));
      expect(await mateScore('position startpos moves d2d4'), lessThan(0));
    });
  });

  group('lifecycle after the handshake', () {
    // A disposed engine is finished. Work that was already in flight could
    // still move its state, and `stop()` did so unconditionally: the Engine
    // Manager disposes its probe engine and the screen's engine is disposed on
    // a switch, so a stale `stop()` reporting `ready` put a dead engine back on
    // the board — with no process behind it.
    test('stop() does not resurrect a disposed engine', () async {
      final fake = _workingEngine();
      final engine =
          GenericUciEngine(EngineProfile(name: 'W', path: fake.path));
      await engine.initialize();
      engine.dispose();

      engine.stop();

      expect(engine.state, EngineState.disposed);
    });

    test('initialising a disposed engine throws instead of spawning', () async {
      final fake = _workingEngine();
      final engine =
          GenericUciEngine(EngineProfile(name: 'W', path: fake.path));
      await engine.initialize();
      engine.dispose();

      await expectLater(engine.initialize(), throwsA(isA<StateError>()));
    });

    test('two initialise calls at once start one process', () async {
      // The Engine Manager probes an engine and the screen that selects it
      // starts the same one. Two handshakes meant two processes, one of them
      // with no reader and alive until the app exited.
      final log = '${_dir.path}/starts.log';
      final file = File('${_dir.path}/once.sh');
      file.writeAsStringSync('#!/bin/bash\n'
          'echo start >> "$log"\n'
          'while IFS= read -r line; do\n'
          '  case "\$line" in\n'
          '    uci) echo "id name Once"; echo "uciok" ;;\n'
          '    isready) echo "readyok" ;;\n'
          '  esac\n'
          'done\n');
      Process.runSync('chmod', ['+x', file.path]);

      final engine =
          GenericUciEngine(EngineProfile(name: 'Once', path: file.path));
      addTearDown(engine.dispose);

      await Future.wait([engine.initialize(), engine.initialize()]);
      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(engine.state, EngineState.ready);
      expect(
        _logLines(log).where((line) => line == 'start').length,
        1,
        reason: 'a second Process.start leaves a process nobody reads',
      );
    });

    test('a retry after a failed initialise is allowed', () async {
      // The in-flight guard must not latch: an engine whose first attempt died
      // is retried by the restart path.
      final fake = _workingEngine();
      final profile =
          EngineProfile(name: 'W', path: '${_dir.path}/missing-binary');
      final engine = GenericUciEngine(profile);
      await expectLater(engine.initialize(), throwsA(isA<Object>()));
      expect(engine.state, EngineState.error);

      // The same object, now pointing at a working binary — the user corrected
      // the path. The in-flight guard must have been cleared by the failure,
      // or every later attempt would return the old failed future.
      profile.path = fake.path;
      await engine.initialize();

      expect(engine.state, EngineState.ready);
      engine.dispose();
    });
  });

  group('evaluation perspective belongs to the search', () {
    // The conversion from the engine's side-to-move score to White's used to be
    // an instance field set by the caller *before* asking for the search. The
    // coordinator stops the previous search and waits for its `bestmove` first,
    // and a real engine keeps printing `info` lines while that happens —
    // measured on Stockfish 11: 16 of them between `stop` and `bestmove`. Those
    // lines belong to the previous position, but were converted with the new
    // one's colour, so the eval bar briefly showed the opposite of the engine's
    // opinion. The colour now travels with the search.
    test('an eval still arriving from the stopped search keeps its colour',
        () async {
      final fake = _script('two_searches', '''
    uci) echo "id name Two Searches"; echo "uciok" ;;
    isready) echo "readyok" ;;
    go*)
      sleep 0.15
      echo "info depth 3 score cp 100 pv e2e4"
      echo "bestmove e2e4"
      ;;
''');
      final engine = GenericUciEngine(
          EngineProfile(name: 'Two', path: fake.path));
      await engine.initialize();
      addTearDown(engine.dispose);

      final scores = <double>[];
      final sub =
          engine.analyze('position startpos', depth: 3).listen((i) => scores.add(i.score));
      // White to move, then Black to move: the engine reports +1.00 for the side
      // to move in both, so White's point of view is +1.00 and then -1.00.
      engine.analyze('position startpos moves d2d4', depth: 3);

      await Future<void>.delayed(const Duration(milliseconds: 700));
      await sub.cancel();

      expect(scores, isNotEmpty, reason: 'the fake engine emits at least one');
      expect(scores.first, closeTo(1.0, 1e-9),
          reason: 'the first eval belongs to the White-to-move search');
      expect(scores.last, closeTo(-1.0, 1e-9),
          reason: 'the last eval belongs to the Black-to-move search');
    });
  });
}
