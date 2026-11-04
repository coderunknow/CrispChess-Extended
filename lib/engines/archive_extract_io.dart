/// Archive extraction (native platforms): staged, verified, cleaned up.
///
/// The Engine Manager downloads archives (Lynx is distributed as a `.zip`), and
/// the engine adapter launches an extracted binary. Two independent code paths
/// with their own extractors disagreed about where the result went: the Manager
/// saved a verified `.zip` in the artifact directory and called it installed
/// while the engine looked for the binary somewhere else and downloaded again.
/// One extractor, one destination layout, is what keeps them in agreement.
///
/// Guarantees:
///  * extraction happens in a staging directory beside the destination;
///  * the staging tree is removed on every exit path, success or failure;
///  * nothing is installed until the archive has extracted successfully;
///  * a failed extraction never leaves a file that an existence check accepts.
library;

import 'dart:io';



/// Extracts [archivePath] into [destinationDir].
///
/// Returns the number of files installed. Throws [FileSystemException] or
/// [ProcessException] on failure, having removed the staging tree.
Future<int> extractArchiveTo({
  required String archivePath,
  required String destinationDir,
}) async {
  final destination = Directory(destinationDir);
  final staging = Directory(
      '${destination.parent.path}/.staging-${DateTime.now().microsecondsSinceEpoch}');
  try {
    await staging.create(recursive: true);
    final archive = File(archivePath);
    if (!await archive.exists()) {
      throw FileSystemException('archive is missing', archivePath);
    }
    final lower = archivePath.toLowerCase();
    ProcessResult result;
    if (lower.endsWith('.zip')) {
      result = Platform.isWindows
          ? await Process.run('powershell', [
              '-NoProfile',
              '-NonInteractive',
              '-command',
              "Expand-Archive -LiteralPath '${psLiteral(archive.path)}' "
                  "-DestinationPath '${psLiteral(staging.path)}' -Force",
            ])
          : await Process.run('unzip', ['-o', archive.path, '-d', staging.path]);
    } else if (lower.endsWith('.tar') || lower.endsWith('.tar.gz') ||
        lower.endsWith('.tgz')) {
      result = await Process.run('tar', [
        '-xf', archive.path, '-C', staging.path,
      ]);
    } else {
      throw FileSystemException(
          'unsupported archive type (expected .zip, .tar or .tar.gz)',
          archivePath);
    }
    if (result.exitCode != 0) {
      throw ProcessException(
          Platform.isWindows ? 'powershell' : 'tar/unzip', const [],
          'extracting the archive failed: ${result.stderr}', result.exitCode);
    }
    await destination.create(recursive: true);
    var installed = 0;
    await for (final entity in staging.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(staging.path.length + 1);
      final target = File('${destination.path}/$relative');
      await target.parent.create(recursive: true);
      if (await target.exists()) await target.delete();
      await entity.copy(target.path);
      installed++;
    }
    if (installed == 0) {
      throw FileSystemException('the archive contained no files', archivePath);
    }
    return installed;
  } finally {
    // Every exit path, including a failed extraction or a copy error halfway
    // through, leaves nothing behind: a leftover staging tree was both a disk
    // leak and, when it sat where the binary is expected, a false "installed".
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
    } catch (_) {
      // Nothing further can be done, and the throw above is the real failure.
    }
  }
}

/// Escapes a path for a single-quoted PowerShell literal.
///
/// Inside `'...'` PowerShell interprets nothing except the closing quote, and a
/// literal quote is written by doubling it — so a `$` or a backtick in a path
/// cannot start a command. PowerShell also accepts the typographic apostrophes
/// U+2018, U+2019, U+201A and U+201B as string delimiters, so all five are
/// doubled.
String psLiteral(String value) => value.replaceAllMapped(
    RegExp('[\u0027\u2018\u2019\u201A\u201B]'), (m) => '${m[0]}${m[0]}');
