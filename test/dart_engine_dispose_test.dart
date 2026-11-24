import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/dart_engine.dart';
import 'package:crispchess/engines/chess_engine.dart';

void main() {
  test('dispose during an active bestMove leaves the engine disposed, not ready',
      () async {
    final engine = DartEngine();
    await engine.initialize();
    final pending = engine.bestMove('position startpos',
        depth: 50, moveTime: const Duration(seconds: 10), skillLevel: 20);
    // dispose() runs before the search can complete (the search only
    // finishes at an await point, and this call is synchronous up to it).
    engine.dispose();

    // The in-flight request may fail (the worker is torn down) or complete;
    // either way its completion must not write `ready` over the dispose.
    // Before the guard, the success path resurrected the engine to `ready`
    // while its worker was gone — usable-looking, permanently broken.
    await pending.then<void>((_) {}, onError: (Object _) {});
    expect(engine.state, EngineState.disposed);

    // And a disposed engine stays dead for the next caller.
    await expectLater(engine.bestMove('position startpos'),
        throwsStateError);
  });
}
