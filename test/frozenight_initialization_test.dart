@TestOn('vm')
library;

import 'dart:io';
import 'package:crispchess/engines/frozenight_engine.dart'
    if (dart.library.js_interop) 'package:crispchess/engines/frozenight_web_engine.dart';
import 'package:crispchess/engines/chess_engine.dart';
import 'package:crispchess/engines/engine_initialization.dart';
import 'package:crispchess/services/engine_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missing library preserves cause, code, stage and identity', () async {
    final path = '${Directory.systemTemp.path}/crisp-missing-frozenight-${DateTime.now().microsecondsSinceEpoch}.dll';
    final engine = FrozenightEngine(libraryPath: path);
    final starts = await Future.wait([engine.initialize().then<Object?>((_) => null, onError: (Object e) => e),
      engine.initialize().then<Object?>((_) => null, onError: (Object e) => e)]);
    expect(starts[0], isA<EngineInitializationException>());
    expect(identical(starts[0], starts[1]), isTrue);
    final failure = starts[0] as EngineInitializationException;
    expect(failure.engine, 'Frozenight');
    expect(failure.version, '7.0.0');
    expect(failure.stage, 'load-library');
    expect(failure.libraryPath, path);
    expect(failure.cause, isA<ArgumentError>());
    expect(failure.toString(), contains(path));
    expect(engine.state, EngineState.error);
    engine.dispose(); engine.dispose();
    expect(engine.state, EngineState.disposed);
  });
  test('gameplay service cannot call an error state a successful start', () async {
    final path = '${Directory.systemTemp.path}/crisp-missing-service.dll';
    final service = EngineService(FrozenightEngine(libraryPath: path));
    final error = service.events.where((e) => e is EngineErrorEvent).cast<EngineErrorEvent>().first;
    expect(await service.initialize(), isFalse);
    final event = await error;
    expect(event.kind, EngineFailure.startup);
    expect(event.message, contains('stage=load-library'));
    expect(event.message, contains(path));
    service.dispose();
  });
}
