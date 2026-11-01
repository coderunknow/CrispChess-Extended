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
    final abi = lib.lookupFunction<Uint32 Function(), int Function()>("frozenight_abi_version")();
    record("abi", {"version": abi});
    if (abi != 2) throw StateError("Expected ABI 2, found $abi");
    final names = ["frozenight_create", "frozenight_set_position_v2",
      "frozenight_search_bounded_v2", "frozenight_get_nodes_v2",
      "frozenight_get_best_move_v2", "frozenight_get_score_v2",
      "frozenight_get_depth_v2", "frozenight_destroy"];
    for (final name in names) {
      record("symbol", {"name": name, "address": lib.lookup<Void>(name).address});
    }
    final create = lib.lookupFunction<Pointer<NativeType> Function(Uint32), Pointer<NativeType> Function(int)>("frozenight_create");
    final position = lib.lookupFunction<Int32 Function(Pointer<NativeType>, Pointer<Utf8>, Pointer<Utf8>), int Function(Pointer<NativeType>, Pointer<Utf8>, Pointer<Utf8>)>("frozenight_set_position_v2");
    final search = lib.lookupFunction<Int32 Function(Pointer<NativeType>, Int32, Uint64), int Function(Pointer<NativeType>, int, int)>("frozenight_search_bounded_v2");
    final best = lib.lookupFunction<Pointer<Utf8> Function(Pointer<NativeType>), Pointer<Utf8> Function(Pointer<NativeType>)>("frozenight_get_best_move_v2");
    final nodes = lib.lookupFunction<Int64 Function(Pointer<NativeType>), int Function(Pointer<NativeType>)>("frozenight_get_nodes_v2");
    final releaseHandle = lib.lookupFunction<Void Function(Pointer<NativeType>), void Function(Pointer<NativeType>)>("frozenight_destroy");
    Pointer<NativeType>? handle;
    dispose = () { final h = handle; if (h != null) { releaseHandle(h); handle = null; } };

    for (var cycle = 0; cycle < 3; cycle++) {
      handle = create(32);
      final rc = handle!.address == 0 ? -1 : 0;
      record('native-init', {'cycle': cycle, 'rc': rc});
      if (rc != 0) throw StateError('native init returned $rc');
      final fen = 'startpos'.toNativeUtf8();
      final moves = 'e2e4 e7e5'.toNativeUtf8();
      try {
        final applied = position(handle!, fen, moves);
        record('position', {'cycle': cycle, 'rc': applied});
        if (applied != 0) throw StateError('set_position returned $applied');
      } finally {
        malloc.free(fen);
        malloc.free(moves);
      }
      final searched = search(handle!, 3, 5000);
      final ptr = best(handle!);
      final move = ptr.address == 0 ? null : ptr.toDartString();
      record('search', {'cycle': cycle, 'rc': searched, 'move': move, 'nodes': nodes(handle!), 'nodeLimit': 5000});
      if (searched != 0 || move == null || move == '0000') {
        throw StateError('search failed: $searched / $move');
      }
      dispose!();
      record('disposed', {'cycle': cycle});
    }
    dispose = null;
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
