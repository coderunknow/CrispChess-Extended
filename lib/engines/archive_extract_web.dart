/// Archive extraction in a browser: there is no process to run a native
/// unzipper and no filesystem to extract into, so this refuses rather than
/// pretending. The Engine Manager already reports browser-managed storage for
/// every artifact, so nothing reaches here in practice.
library;

/// Always throws: a browser cannot extract a native archive.
Future<int> extractArchiveTo({
  required String archivePath,
  required String destinationDir,
}) async {
  throw UnsupportedError(
      'A browser cannot extract a native archive; downloads are '
      'browser-managed.');
}

/// Kept so the facade has one shape on every platform.
String psLiteral(String value) => value;
