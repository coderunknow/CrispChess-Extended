import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/services/engine_service.dart';

void main() {
  _engineSwitchingTests();

  group('EngineEvent types', () {
    test('EvalUpdateEvent holds data', () {
      final e = EvalUpdateEvent(eval: 1.5, depth: 20, bestMove: 'e2e4');
      expect(e.eval, 1.5);
      expect(e.depth, 20);
      expect(e.bestMove, 'e2e4');
    });

    test('BestMoveEvent holds move', () {
      expect(BestMoveEvent('d2d4').move, 'd2d4');
    });

    test('EngineErrorEvent holds message', () {
      expect(EngineErrorEvent('fail').message, 'fail');
    });

    test('pattern matching exhaustive', () {
      final events = <EngineEvent>[
        EvalUpdateEvent(eval: 0.5, depth: 10, bestMove: 'e2e4'),
        BestMoveEvent('d2d4'),
        StateChangeEvent(EngineState.ready),
        EngineErrorEvent('test'),
      ];
      final results = events.map((e) => switch (e) {
        EvalUpdateEvent() => 'eval',
        BestMoveEvent() => 'best',
        StateChangeEvent() => 'state',
        EngineErrorEvent() => 'error',
      }).toList();
      expect(results, ['eval', 'best', 'state', 'error']);
    });
  });

  group('StateChangeEvent', () {
    test('holds all EngineState values', () {
      for (final s in EngineState.values) {
        expect(StateChangeEvent(s).state, s);
      }
    });
  });

  group('Debounce behavior', () {
    test('rapid events debounce to one', () async {
      final controller = StreamController<EngineEvent>.broadcast();
      final events = <EngineEvent>[];
      controller.stream.listen(events.add);

      Timer? debounce;
      double? buffered;
      for (int i = 0; i < 50; i++) {
        buffered = i * 0.02;
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 50), () {
          controller.add(EvalUpdateEvent(
              eval: buffered!, depth: 50, bestMove: 'e2e4'));
        });
      }

      await Future.delayed(const Duration(milliseconds: 150));
      expect(events.length, 1);
      expect((events.first as EvalUpdateEvent).eval, closeTo(0.98, 0.01));

      debounce?.cancel();
      await controller.close();
    });
  });

}

/// An engine that starts, and one that cannot.
///
/// `EngineService.initialize` used to have no way to say "this did not work":
/// it reported the failure as an event and returned normally, so a caller that
/// had just switched engines could not tell the new one never started.
class _StartingEngine implements ChessEngine {
  final _notifier = ValueNotifier<EngineState>(EngineState.idle);

  @override
  Future<void> initialize() async {
    _notifier.value = EngineState.ready;
  }

  @override
  void dispose() => _notifier.value = EngineState.disposed;

  @override
  void stop() {}

  @override
  void setOption(String name, String value) {}

  @override
  Future<String> bestMove(String p,
          {int? depth, Duration? moveTime, int? skillLevel}) async =>
      'e2e4';

  @override
  Stream<EvalInfo> analyze(String p, {int? depth, bool infinite = false}) =>
      const Stream.empty();

  @override
  String get name => 'Starting';

  @override
  String get version => '1';

  @override
  String get license => 'MIT';

  @override
  int get estimatedElo => 1;

  @override
  EngineState get state => _notifier.value;

  @override
  ValueNotifier<EngineState> get stateNotifier => _notifier;

  @override
  bool get canPonder => false;
}

class _BrokenEngine extends _StartingEngine {
  @override
  Future<void> initialize() async {
    _notifier.value = EngineState.error;
    throw StateError('binary not found');
  }

  @override
  String get name => 'Broken';
}

void _engineSwitchingTests() {
  group('EngineService.switchEngine', () {
    test('reports that the new engine started', () async {
      final service = EngineService(_StartingEngine());
      expect(await service.initialize(), isTrue, reason: 'initial start');

      expect(await service.switchEngine(_StartingEngine()), isTrue);
      service.dispose();
    });

    test('reports a new engine that failed to start', () async {
      final service = EngineService(_StartingEngine());
      await service.initialize();

      final events = <EngineEvent>[];
      final sub = service.events.listen(events.add);

      final started = await service.switchEngine(_BrokenEngine());
      await Future<void>.delayed(Duration.zero);

      expect(started, isFalse,
          reason: 'the caller has to be able to say so instead of assuming');
      expect(service.engine.state, EngineState.error);
      expect(
        events.whereType<EngineErrorEvent>().any(
            (e) => e.kind == EngineFailure.startup),
        isTrue,
        reason: 'the failure is still reported for the UI',
      );

      await sub.cancel();
      service.dispose();
    });

    test('a recovered switch reports success again', () async {
      final service = EngineService(_StartingEngine());
      await service.initialize();

      expect(await service.switchEngine(_BrokenEngine()), isFalse);
      expect(await service.switchEngine(_StartingEngine()), isTrue);
      expect(service.engine.state, EngineState.ready);

      service.dispose();
    });
  });
}
