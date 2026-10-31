import 'engine_lab_storage_stub.dart'
    if (dart.library.io) 'engine_lab_storage_native.dart'
    if (dart.library.js_interop) 'engine_lab_storage_web.dart' as platform;

Future<String?> readEngineLabData() => platform.readEngineLabData();
Future<String?> readEngineLabBackup() => platform.readEngineLabBackup();
Future<void> writeEngineLabData(String value) => platform.writeEngineLabData(value);
