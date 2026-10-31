/// Web stub for GenericUciEngine — not available on web platform.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'chess_engine.dart';
import 'generic_uci_engine_stub.dart';
import 'uci_capabilities.dart';
import 'uci_option.dart';

export 'generic_uci_engine_stub.dart' show EngineProfile;

class GenericUciEngine implements ChessEngine, UciOptionAware {
  final EngineProfile profile;
  final List<UciOption> options = [];

  /// Stable, not rebuilt per access: a fresh notifier on every `stateNotifier`
  /// read means listeners are attached to an object nobody ever updates, so a
  /// state change is never observed.
  final _stateNotifier = ValueNotifier<EngineState>(EngineState.error);

  GenericUciEngine(this.profile);

  @override String get name => profile.displayName;
  @override String get version => '';
  @override String get license => 'Unknown';
  @override int get estimatedElo => 0;
  @override EngineState get state => _stateNotifier.value;
  @override ValueNotifier<EngineState> get stateNotifier => _stateNotifier;
  @override Future<void> initialize() async =>
      throw UnsupportedError('Custom UCI engines not available on web');
  @override Future<String> bestMove(String p, {int? depth, Duration? moveTime, int? skillLevel}) async =>
      throw UnsupportedError('Custom UCI engines not available on web');
  @override Stream<EvalInfo> analyze(String p, {int? depth, bool infinite = false}) =>
      const Stream.empty();
  @override bool get canPonder => false;
  @override void stop() {}
  @override void setOption(String name, String value) {}
  @override void dispose() {}
  void pressButton(String name) {}

  /// A browser cannot run a user-supplied engine at all, so there is nothing to
  /// advertise and nothing to apply. Implemented so the benchmark can ask
  /// uniformly and record "unsupported" rather than assume.
  @override
  List<String> get advertisedOptionNames => const [];

  @override
  bool advertisesOption(String name) => false;

  @override
  void applyOption(String name, String value) {}
}
