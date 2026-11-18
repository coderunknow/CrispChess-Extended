// Browser stub for the diagnostic log sink.
//
// A browser has no writable application support directory, so logging stays
// in memory there. The interface matches the native sink; nothing else
// changes (diag_log_sink.dart picks this file in a browser).
library;

/// Persistence contract for diagnostic log lines (web: memory only).
class DiagLogSink {
  DiagLogSink({
    int maxFileBytes = 1024 * 1024,
    int maxGenerations = 3,
    int flushBatch = 32,
    Duration flushInterval = const Duration(seconds: 2),
  });

  Future<void> appendLine(String line) async {}

  Future<void> flush() async {}

  Future<List<String>> readLines({int maxLines = 5000}) async => const [];

  Future<void> clear() async {}
}
