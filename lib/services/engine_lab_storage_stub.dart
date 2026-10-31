Future<String?> readEngineLabData() async => null;
Future<String?> readEngineLabBackup() async => null;
Future<void> writeEngineLabData(String value) async =>
    throw UnsupportedError('Benchmark history persistence is not supported on this platform');
