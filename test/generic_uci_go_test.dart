// What the generic UCI engine actually sends, and whose Skill Level wins.
//
// Two defects lived here and neither was visible from the Dart types:
//
//  * `go depth 8` was sent even when the caller asked for a time control, so a
//    timed tournament measured a depth budget while the report said "100 ms per
//    move". `MatchConfig` now clears the depth, and this file pins down why:
//    the engine obeys `depth` when it is given one.
//  * the strength slider wrote `Skill Level` over the value the user had saved
//    in the engine profile, so a hand-tuned engine silently played at a
//    different strength than the profile said.
//
// The engine is driven against a small shell script, so what is asserted is
// what went over the process's stdin.
@TestOn('vm')
library;

import 'dart:io';

import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/generic_uci_engine.dart';
import 'package:flutter_test/flutter_test.dart';

late Directory _dir;

/// A UCI engine that logs every command and answers with a fixed move.
({String path, String log}) _engine() {
  final log = '${_dir.path}/commands.log';
  final file = File('${_dir.path}/engine.sh');
  file.writeAsStringSync('#!/bin/bash\n'
      'while IFS= read -r line; do\n'
      '  echo "\$line" >> "$log"\n'
      '  case "\$line" in\n'
      '    uci)\n'
      '      echo "id name Logger 1.0"\n'
      '      echo "option name Skill Level type spin default 20 min 0 max 20"\n'
      '      echo "uciok"\n'
      '      ;;\n'
      '    isready) echo "readyok" ;;\n'
      '    go*) echo "bestmove e2e4" ;;\n'
      '    quit) exit 0 ;;\n'
      '  esac\n'
      'done\n');
  Process.runSync('chmod', ['+x', file.path]);
  return (path: file.path, log: log);
}

List<String> _logged(String path) =>
    File(path).existsSync() ? File(path).readAsLinesSync() : const [];

/// The child writes as it reads; wait for the line the assertion is about
/// rather than racing it.
Future<List<String>> _loggedWhen(
  String path,
  bool Function(List<String> lines) predicate,
) async {
  for (var i = 0; i < 60; i++) {
    final lines = _logged(path);
    if (predicate(lines)) return lines;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  return _logged(path);
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('crispchess_go'));
  tearDown(() => _dir.deleteSync(recursive: true));

  group('the go command', () {
    test('a time control sends movetime and no depth', () async {
      final fake = _engine();
      final engine = GenericUciEngine(EngineProfile(name: 'Logger', path: fake.path));
      await engine.initialize();
      addTearDown(engine.dispose);

      expect(
        await engine.bestMove('position startpos',
            moveTime: const Duration(milliseconds: 250)),
        'e2e4',
      );
      final lines = await _loggedWhen(
          fake.log, (lines) => lines.any((l) => l.startsWith('go ')));
      expect(lines, contains('go movetime 250'));
      expect(lines.where((l) => l.startsWith('go ')), hasLength(1));
    });

    test('an explicit depth sends depth', () async {
      final fake = _engine();
      final engine = GenericUciEngine(EngineProfile(name: 'Logger', path: fake.path));
      await engine.initialize();
      addTearDown(engine.dispose);

      await engine.bestMove('position startpos', depth: 3);
      final lines = await _loggedWhen(
          fake.log, (lines) => lines.contains('go depth 3'));
      expect(lines, contains('go depth 3'));
    });

    test('a depth wins over a time control, which is why only one is set',
        () async {
      final fake = _engine();
      final engine = GenericUciEngine(EngineProfile(name: 'Logger', path: fake.path));
      await engine.initialize();
      addTearDown(engine.dispose);

      await engine.bestMove('position startpos',
          depth: 3, moveTime: const Duration(seconds: 5));
      final lines = await _loggedWhen(
          fake.log, (lines) => lines.any((l) => l.startsWith('go ')));
      // The engine would spend as long as depth 3 takes and ignore the clock:
      // this is the behaviour `MatchConfig.timed` exists to avoid asking for.
      expect(lines, contains('go depth 3'));
      expect(lines, isNot(contains('go movetime 5000')));
    });
  });

  group('Skill Level', () {
    test('the strength slider is applied when the profile has no opinion',
        () async {
      final fake = _engine();
      final engine = GenericUciEngine(EngineProfile(name: 'Logger', path: fake.path));
      await engine.initialize();
      addTearDown(engine.dispose);

      await engine.bestMove('position startpos',
          moveTime: const Duration(milliseconds: 50), skillLevel: 12);
      final lines = await _loggedWhen(
          fake.log, (lines) => lines.contains('setoption name Skill Level value 12'));
      expect(lines, contains('setoption name Skill Level value 12'));
    });

    test('a profile Skill Level is not overwritten by the slider', () async {
      final fake = _engine();
      final engine = GenericUciEngine(EngineProfile(
        name: 'Logger',
        path: fake.path,
        optionOverrides: {'Skill Level': '0'},
      ));
      await engine.initialize();
      addTearDown(engine.dispose);

      await engine.bestMove('position startpos',
          moveTime: const Duration(milliseconds: 50), skillLevel: 12);
      final lines = await _loggedWhen(
          fake.log, (lines) => lines.any((l) => l.startsWith('go ')));
      expect(lines, contains('setoption name Skill Level value 0'));
      expect(lines, isNot(contains('setoption name Skill Level value 12')),
          reason: 'the user saved a Skill Level; the slider must not win');
    });
  });

  group('draining a stopped search', () {
    test('an idle engine drains immediately', () async {
      final fake = _engine();
      final engine = GenericUciEngine(EngineProfile(name: 'Logger', path: fake.path));
      await engine.initialize();
      addTearDown(engine.dispose);

      final stopwatch = Stopwatch()..start();
      await engine.drainSearch(timeout: const Duration(seconds: 2));
      stopwatch.stop();
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('a disposed engine drains without throwing', () async {
      final fake = _engine();
      final engine = GenericUciEngine(EngineProfile(name: 'Logger', path: fake.path));
      await engine.initialize();
      engine.dispose();
      await engine.drainSearch(timeout: const Duration(seconds: 2));
      expect(engine.state, EngineState.disposed);
    });
  });
}
