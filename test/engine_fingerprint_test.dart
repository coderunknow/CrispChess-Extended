@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:crispchess/engines/engine_fingerprint.dart';
import 'package:crispchess/engines/generic_uci_engine_stub.dart';

void main() {
  test('SHA-256 is cached by executable file metadata and changes are detected', () async {
    final directory = await Directory.systemTemp.createTemp('engine_fingerprint');
    addTearDown(() => directory.delete(recursive: true));
    final binary = File('${directory.path}/engine')..writeAsStringSync('test-binary-v1');
    final profile = EngineProfile(name: 'fingerprint test', path: binary.path);

    expect(await refreshEngineFingerprint(profile), isFalse);
    final first = profile.binaryFingerprint;
    expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
    final firstMetadata = profile.binaryFingerprintMetadata;
    expect(await refreshEngineFingerprint(profile), isFalse);
    expect(profile.binaryFingerprint, first, reason: 'same metadata should reuse cached digest');
    expect(profile.binaryFingerprintMetadata, firstMetadata);

    binary.writeAsStringSync('test-binary-v2-with-new-content');
    expect(await refreshEngineFingerprint(profile), isTrue);
    expect(profile.binaryFingerprint, isNot(first));
  });
}
