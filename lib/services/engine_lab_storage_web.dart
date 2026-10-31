import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _dataKey = 'engine_lab_history_v1';
const _backupKey = 'engine_lab_history_v1_backup';

Future<String?> readEngineLabData() async =>
    (await SharedPreferences.getInstance()).getString(_dataKey);

Future<String?> readEngineLabBackup() async =>
    (await SharedPreferences.getInstance()).getString(_backupKey);

Future<void> writeEngineLabData(String value) async {
  final prefs = await SharedPreferences.getInstance();
  final old = prefs.getString(_dataKey);
  var oldIsValid = false;
  if (old != null) {
    try {
      final decoded = jsonDecode(old);
      oldIsValid = decoded is Map && decoded['schemaVersion'] == 1 && decoded['runs'] is List;
    } catch (_) {
      oldIsValid = false;
    }
  }
  if (oldIsValid && old != null && !await prefs.setString(_backupKey, old)) {
    throw StateError('Could not preserve previous benchmark history snapshot');
  }
  if (!await prefs.setString(_dataKey, value)) {
    throw StateError('Could not save benchmark history to browser storage');
  }
}
