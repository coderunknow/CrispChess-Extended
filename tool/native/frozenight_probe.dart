// Real-library smoke probe. Run with dart --packages=.dart_tool/package_config.json
// tool/native/frozenight_probe.dart <absolute-library-path> [missing|ready].
// No mock, Flutter binding, downloaded substitute, or engine fallback is used.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

void main(List<String> args) {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('Usage: frozenight_probe.dart LIBRARY [missing|ready]');
    exitCode = 2;
    return;
  }
  final expected = args.length == 2 ? args[1] : 'ready';
  final events = <Map<String, Object?>>[];
  final all = Stopwatch()..start();
  DynamicLibrary? lib;
  void Function()? dispose;
  void record(String stage, [Map<String, Object?> detail = const {}]) {
    final event = {'stage': stage, 'micros': all.elapsedMicroseconds, ...detail};
    events.add(event);
    stdout.writeln(jsonEncode(event));
  }

  record('start', {
    'library': args[0],
    'platform': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'dart': Platform.version,
    'pid': pid,
    'expected': expected,
  });
  try {
    lib = DynamicLibrary.open(args[0]);
    record('library-loaded');
    final names = [
      'frozenight_init', 'frozenight_set_position', 'frozenight_search',
      'frozenight_search_bounded', 'frozenight_get_nodes',
      'frozenight_get_best_move', 'frozenight_get_score',
      'frozenight_get_depth', 'frozenight_dispose',
    ];
    for (final name in names) {
      record('symbol', {'name': name, 'address': lib.lookup<Void>(name).address});
    }
    final init = lib.lookupFunction<Int32 Function(Uint32), int Function(int)>('frozenight_init');
    final position = lib.lookupFunction<
        Int32 Function(Pointer<Utf8>, Pointer<Utf8>),
        int Function(Pointer<Utf8>, Pointer<Utf8>)>('frozenight_set_position');
    final search = lib.lookupFunction<Int32 Function(Int32, Uint64), int Function(int, int)>('frozenight_search_bounded');
    final best = lib.lookupFunction<Pointer<Utf8> Function(), Pointer<Utf8> Function()>('frozenight_get_best_move');
    final nodes = lib.lookupFunction<Int64 Function(), int Function()>('frozenight_get_nodes');
    dispose = lib.lookupFunction<Void Function(), void Function()>('frozenight_dispose');
    for (var cycle = 0; cycle < 3; cycle++) {
      final rc = init(32);
      record('native-init', {'cycle': cycle, 'rc': rc});
      if (rc != 0) throw StateError('native init returned $rc');
      final fen = 'startpos'.toNativeUtf8();
      final moves = 'e2e4 e7e5'.toNativeUtf8();
      try {
        final applied = position(fen, moves);
        record('position', {'cycle': cycle, 'rc': applied});
        if (applied != 0) throw StateError('set_position returned $applied');
      } finally {
        malloc.free(fen);
        malloc.free(moves);
      }
      final searched = search(3, 5000);
      final ptr = best();
      final move = ptr.address == 0 ? null : ptr.toDartString();
      record('search', {'cycle': cycle, 'rc': searched, 'move': move, 'nodes': nodes(), 'nodeLimit': 5000});
      if (searched != 0 || move == null || move == '0000') {
        throw StateError('search failed: $searched / $move');
      }
      dispose();
      dispose = null;
      record('disposed', {'cycle': cycle});
    }
    record('result', {'outcome': 'ready'});
    if (expected != 'ready') exitCode = 1;
  } catch (error, stack) {
    record('original-error', {'type': error.runtimeType.toString(), 'message': '$error', 'stack': '$stack'});
    record('result', {'outcome': 'failed'});
    if (expected != 'missing') exitCode = 1;
  } finally {
    dispose?.call();
    record('exit', {'code': exitCode});
  }
}
