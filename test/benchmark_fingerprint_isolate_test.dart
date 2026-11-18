import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart' as crypto;

import 'package:crispchess/bench/benchmark_fingerprint.dart' show sha256OfFile;

/// Regression tests for the worker-isolate fingerprinting (dev6).
///
/// The isolate refactor briefly shipped without an `await` on the streamed
/// digest, so every binary hashed to the string representation of a
/// `Future<Digest>` and every engine therefore looked "changed" after each
/// open. These tests pin the actual digest bytes, the missing-file behaviour
/// and concurrent hashing.
void main() {
  test('sha256OfFile matches the real digest of the bytes on disk', () async {
    final dir = await Directory.systemTemp.createTemp('fingerprint-');
    addTearDown(() => dir.delete(recursive: true));
    final bytes = List<int>.generate(1 << 20, (i) => i & 0xFF);
    final file = File('${dir.path}/engine.bin');
    await file.writeAsBytes(bytes, flush: true);

    final digest = await sha256OfFile(file.path);

    expect(digest, crypto.sha256.convert(bytes).toString());
  });

  test('sha256OfFile returns null for a missing file, not a pseudo digest',
      () async {
    final digest =
        await sha256OfFile('/nonexistent/dev6/missing-engine.bin');
    expect(digest, isNull);
  });

  test('concurrent hashes of different files stay correct', () async {
    final dir = await Directory.systemTemp.createTemp('fingerprint-');
    addTearDown(() => dir.delete(recursive: true));
    final expected = <String, String>{};
    final futures = <Future<String?>>[];
    for (var i = 0; i < 4; i++) {
      final bytes = List<int>.generate(64 * 1024, (j) => (j * (i + 1)) & 0xFF);
      final file = File('${dir.path}/engine_$i.bin');
      await file.writeAsBytes(bytes, flush: true);
      expected['${file.path}'] = crypto.sha256.convert(bytes).toString();
      futures.add(sha256OfFile(file.path));
    }
    final digests = await futures.wait;
    expect(digests.length, expected.length);
    var index = 0;
    for (final entry in expected.entries) {
      expect(digests[index++], entry.value);
    }
  });
}
