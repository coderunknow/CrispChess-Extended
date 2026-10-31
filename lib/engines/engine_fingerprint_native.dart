import 'dart:io';

import 'package:crypto/crypto.dart';

import 'generic_uci_engine_stub.dart' show EngineProfile;

Future<bool> refreshEngineFingerprint(EngineProfile profile, {bool force = false}) async {
  final file = File(profile.path);
  final stat = await file.stat();
  if (stat.type != FileSystemEntityType.file) return false;
  final metadata = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
  if (!force && profile.binaryFingerprint != null &&
      profile.binaryFingerprintMetadata == metadata) {
    return false;
  }
  final previous = profile.binaryFingerprint;
  final current = (await sha256.bind(file.openRead()).first).toString();
  profile.binaryFingerprint = current;
  profile.binaryFingerprintMetadata = metadata;
  return previous != null && previous != current;
}
