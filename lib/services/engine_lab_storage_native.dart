import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<File> _dataFile() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}engine_lab_history.json');
}

Future<String?> readEngineLabData() async {
  final file = await _dataFile();
  if (!await file.exists()) return null;
  return file.readAsString();
}

Future<String?> readEngineLabBackup() async {
  final file = await _dataFile();
  final backup = File('${file.path}.bak');
  if (!await backup.exists()) return null;
  return backup.readAsString();
}

/// Flush a complete new snapshot before replacing the old file. Keep the last
/// known-good snapshot as a recovery copy; never truncate the only copy first.
Future<bool> _hasValidEnvelope(File file) async {
  try {
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map && decoded['schemaVersion'] == 1 && decoded['runs'] is List;
  } catch (_) {
    return false;
  }
}

Future<void> writeEngineLabData(String value) async {
  final file = await _dataFile();
  await file.parent.create(recursive: true);
  final temp = File('${file.path}.tmp');
  await temp.writeAsString(value, flush: true);
  final backup = File('${file.path}.bak');
  if (await file.exists()) {
    if (await _hasValidEnvelope(file)) {
      if (await backup.exists()) await backup.delete();
      await file.rename(backup.path);
    } else {
      // Keep an existing recovery copy if the primary was already corrupt.
      await file.delete();
    }
  }
  try {
    await temp.rename(file.path);
  } catch (_) {
    if (!(await file.exists()) && await backup.exists()) {
      await backup.rename(file.path);
    }
    rethrow;
  }
}
