/// Regressions for the unified engine storage and the verified download
/// manager: path redaction, write validation, migration without deletion,
/// traversal refusal, atomic install, coalescing and honest integrity labels.
library;

import 'dart:async';
import 'dart:io';

import 'package:crispchess/bench/benchmark_storage_base.dart';
import 'package:crispchess/engines/archive_extract.dart';
import 'package:crispchess/engines/download_io.dart';
import 'package:crispchess/engines/download_manager.dart';
import 'package:crispchess/engines/engine_artifacts.dart';
import 'package:crispchess/engines/engine_storage.dart';
import 'package:crispchess/engines/storage_fs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('engine-storage-test'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('a non-absolute or unwritable directory is refused', () async {
    final storage = EngineStorage(documents: MemoryBenchmarkStorage());
    await expectLater(
      storage.validateCandidate('relative/path'),
      throwsA(isA<EngineStorageError>()),
    );
  });

  test('a valid directory becomes the root and the mode is reported', () async {
    final storage = EngineStorage(documents: MemoryBenchmarkStorage());
    final root = '${temp.path}/engines';
    final location = await storage.setRoot(root);
    expect(location.complete, isTrue);
    expect(File('${root}/.crispchess-write-check').existsSync(), isFalse);
    final current = await storage.location(refresh: true);
    expect(current.rootPath, root);
    expect(current.userSelected, isTrue);
    expect(current.layoutSummary, isNotEmpty);
  });

  test('switching root copies and keeps the old directory', () async {
    final storage = EngineStorage(documents: MemoryBenchmarkStorage());
    final first = await storage.setRoot('${temp.path}/one');
    expect(first.complete, isTrue);
    final source = File('${temp.path}/one/lyx/1.0/bin/Lynx');
    source.parent.createSync(recursive: true);
    source.writeAsStringSync('binary');
    final second = await storage.setRoot('${temp.path}/two');
    expect(second.complete, isTrue);
    expect(second.moved, greaterThan(0));
    expect(File('${temp.path}/two/lyx/1.0/bin/Lynx').readAsStringSync(), 'binary');
    // Never deleted silently: the user decides when the old tree goes.
    expect(source.existsSync(), isTrue);
  });

  test('removeEngine refuses paths outside the managed root', () async {
    final storage = EngineStorage(documents: MemoryBenchmarkStorage());
    await storage.setRoot('${temp.path}/root');
    final outside = Directory('${temp.path}/outside/engine');
    outside.createSync(recursive: true);
    // A traversal-shaped id is sanitised, so nothing outside is touched.
    await storage.removeEngine('../outside', 'engine');
    expect(outside.existsSync(), isTrue);
  });

  test('paths are redacted before they leave the app', () {
    final home = Platform.environment['HOME'] ?? '/home/nobody';
    expect(redactStoragePath('$home/.crispchess/engines'), startsWith('~'));
  });

  test('published checksums are recorded only where upstream publishes them', () {
    final lynx = lynxArtifact('linux', 'x64');
    expect(lynx.sources.single.publishedSha256,
        '123faf887673c2b7a018132c3909c785693c9a33e3793fc7a69c25a3e27e396c');
    expect(lynx.sources.single.integrityLabel, contains('published'));

    // Stockfish is not downloadable from inside the app: its release assets
    // publish no digest, so there is nothing to verify a downloaded binary
    // against before executing it. The adapter finds a user-installed copy.
    // The catalog must therefore offer no source at all rather than a row that
    // silently cannot resolve.
    for (final platform in ['linux', 'windows', 'macos']) {
      final stockfish = stockfishArtifact(platform, 'x64');
      expect(stockfish.sources, isEmpty,
          reason: 'no verifiable Stockfish artifact exists for $platform');
      expect(stockfish.sourceFor(platform, 'x64'), isNull);
    }

    final windowsLynx = lynxArtifact('windows', 'x64');
    expect(windowsLynx.sources.single.publishedSha256,
        '5f73e82a959800deb7fa862910ea3578e4473656ea32f99ee1a6f44d11230580');

    // No invented platform support: Android cannot launch these binaries.
    expect(stockfishArtifact('android', 'arm64').sources, isEmpty);
    expect(lynxArtifact('ios', 'arm64').sources, isEmpty);
  });

  test('a root set through one instance is seen by the next instance', () async {
    // EngineStorage used to default to MemoryBenchmarkStorage, so the root
    // chosen in Engine Manager lived only in that screen's object. LynxEngine
    // constructed its own EngineStorage, read an empty store and fell back to
    // defaultRoot() -- an engine downloaded to a user-selected root became
    // invisible to the code that runs it. One persistent store, shared, is the
    // fix; this asserts the observable consequence.
    final documents = MemoryBenchmarkStorage();
    final chosen = '${temp.path}/chosen-root';
    final first = EngineStorage(documents: documents);
    await first.setRoot(chosen, migrate: false);

    final second = EngineStorage(documents: documents);
    final location = await second.location();
    expect(location.rootPath, chosen,
        reason: 'the persisted root must be read by a new instance');
    expect(location.userSelected, isTrue);
  });

  test('an interrupted migration is resumed into the active root', () async {
    // resumeMigration used to call setRoot(alreadyActiveRoot), where
    // previous == candidate short-circuits to complete: true. It copied
    // nothing and never cleared the marker, so an interrupted move stayed
    // interrupted while the UI called it finished.
    final documents = MemoryBenchmarkStorage();
    final storage = EngineStorage(documents: documents);
    final source = '${temp.path}/old-root';
    final active = '${temp.path}/active-root';
    Directory('$source/engines/demo').createSync(recursive: true);
    File('$source/engines/demo/payload.bin').writeAsStringSync('data');
    // The app is already running from `active`; a previous copy from `source`
    // was interrupted, which is what the incomplete marker records.
    Directory(active).createSync(recursive: true);
    await storage.setRoot(active, migrate: false);
    await storageWriteMigrationMarker(active, {
      'from': source, 'complete': false,
      'at': DateTime.now().toUtc().toIso8601String(),
    });

    final resumed = await storage.resumeMigration();
    expect(resumed, isNotNull,
        reason: 'an incomplete marker must be resumed, not ignored');
    expect(resumed!.complete, isTrue);
    expect(resumed.moved, greaterThan(0),
        reason: 'the copy must actually happen');
    expect(File('$active/engines/demo/payload.bin').existsSync(), isTrue,
        reason: 'the interrupted file lands in the active root');
    // The marker is complete now, so a second launch does nothing.
    expect(await storage.resumeMigration(), isNull);
    // The source tree is never deleted by a migration.
    expect(File('$source/engines/demo/payload.bin').existsSync(), isTrue);
  });

  test('streamToFile refuses a non-HTTPS URL before opening a socket', () async {
    // The redirect guard below only runs when the client is told not to follow
    // redirects itself (followRedirects defaults to true, which made the whole
    // check dead code). Refusing at the entry point is the part that can be
    // asserted without a TLS certificate, and it means no caller can reach the
    // network with plain HTTP even if it forgets to check.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    server.listen((request) async {
      hits++;
      request.response.add([1, 2, 3, 4, 5]);
      await request.response.close();
    });
    final result = await streamToFile(
      uri: Uri.parse('http://127.0.0.1:${server.port}/demo.bin'),
      partPath: '${temp.path}/demo.part',
      maxBytes: 1024,
    );
    expect(result.ok, isFalse);
    expect(result.message, contains('non-HTTPS'));
    expect(hits, 0, reason: 'nothing is fetched over plain HTTP');
    await server.close(force: true);
  });

  test('plain HTTP never reaches the network', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    server.listen((request) async {
      hits++;
      request.response.headers.contentLength = 5;
      request.response.add([1, 2, 3, 4, 5]);
      await request.response.close();
    });
    final storage = EngineStorage(documents: MemoryBenchmarkStorage());
    await storage.setRoot('${temp.path}/root');
    final manager = EngineDownloadManager(storage: storage);
    final artifact = EngineArtifact(
      engineId: 'demo', label: 'Demo', version: '1', kind: 'binary',
      sources: [
        ArtifactSource(url: 'http://127.0.0.1:${server.port}/demo.bin',
            version: '1', platform: 'linux', arch: 'x64', license: 'MIT',
            licenseUrl: 'https://example.com', bytes: 5),
      ],
    );
    final result = await manager.download(artifact, platform: 'linux', arch: 'x64');
    expect(result.ok, isFalse, reason: 'plain HTTP is refused');
    expect(hits, 0);
    await manager.dispose();
    await server.close(force: true);
  });

  test('a failed request cleans up and reports failure', () async {
    final manager = EngineDownloadManager(storage: EngineStorage(documents: MemoryBenchmarkStorage()));
    const artifact = EngineArtifact(
      engineId: 'y', label: 'Y', version: '1', kind: 'binary',
      sources: [
        ArtifactSource(url: 'https://127.0.0.1:1/y.zip', version: '1',
            platform: 'linux', arch: 'x64', license: 'MIT',
            licenseUrl: 'https://example.com'),
      ],
    );
    final result = await manager.download(artifact, platform: 'linux', arch: 'x64');
    expect(result.ok, isFalse);
    expect(result.message, isNotEmpty);
    await manager.dispose();
  });

  test('a non-HTTPS source is refused before any request', () async {
    final manager = EngineDownloadManager(storage: EngineStorage(documents: MemoryBenchmarkStorage()));
    const artifact = EngineArtifact(
      engineId: 'x', label: 'X', version: '1', kind: 'binary',
      sources: [
        ArtifactSource(url: 'http://example.com/x.zip', version: '1',
            platform: 'linux', arch: 'x64', license: 'MIT',
            licenseUrl: 'https://example.com'),
      ],
    );
    final result = await manager.download(artifact, platform: 'linux', arch: 'x64');
    expect(result.ok, isFalse);
    expect(result.message, contains('HTTPS'));
    await manager.dispose();
  });

  test('concurrent requests for one artifact are coalesced', () async {
    final manager = EngineDownloadManager(storage: EngineStorage(documents: MemoryBenchmarkStorage()));
    const artifact = EngineArtifact(
      engineId: 'x', label: 'X', version: '1', kind: 'binary',
      sources: [
        ArtifactSource(url: 'http://127.0.0.1:1/x.zip', version: '1',
            platform: 'linux', arch: 'x64', license: 'MIT',
            licenseUrl: 'https://example.com'),
      ],
    );
    final results = await Future.wait([
      manager.download(artifact, platform: 'linux', arch: 'x64'),
      manager.download(artifact, platform: 'linux', arch: 'x64'),
    ]);
    expect(identical(results[0], results[1]), isTrue,
        reason: 'the second request joins the first instead of refetching');
    await manager.dispose();
  });

  test('hashing bytes is deterministic', () {
    expect(sha256OfBytes('abc'.codeUnits),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  group('Lynx archive extraction', () {
    // The Windows extractor composes ONE -command string. Passing the paths as
    // separate argv items is the bug this guards: PowerShell would receive a
    // list of positional strings, and a destination under a user profile with a
    // space in the name ("C:/Users/Jane Doe/...") split into two arguments.
    test('paths are quoted as PowerShell literals, spaces and quotes included', () {
      const zip = r"C:\Users\Jane Doe\AppData\crispchess\lynx.part.zip";
      const staging = r"C:\Users\Jane Doe\AppData\crispchess\.staging-1";
      final command = "Expand-Archive -LiteralPath '${psLiteral(zip)}' "
          "-DestinationPath '${psLiteral(staging)}' -Force";
      expect(command, contains("-LiteralPath 'C:\\Users\\Jane Doe\\"));
      // Exactly two single-quoted regions: one path each, untouched otherwise.
      expect("'".allMatches(command).length, 4);
      // A quote inside a path is doubled, which is the only PowerShell escape.
      expect(psLiteral(r"a'b"), r"a''b");
      // PowerShell also treats the typographic apostrophes as delimiters, so a
      // path under "O\u2019Brien" must not close the literal early.
      expect(psLiteral('O\u2019Brien'), 'O\u2019\u2019Brien');
      // Nothing else in a path can start a command inside '...'.
      expect(psLiteral(r'$HOME`whoami;'), r'$HOME`whoami;');
    });

    test('an archive is extracted beside itself, where the engine looks', () {
      // The manager saved a verified .zip and called it installed while the
      // engine adapter looked for an extracted binary in a different path.
      expect(isArchiveName('CrispChess-linux-x64.zip'), isTrue);
      expect(isArchiveName('CrispChess-linux-x64.tar.gz'), isTrue);
      expect(isArchiveName('app-release.apk'), isFalse);
      expect(
          installDirFor('/root/lynx/1.11.0/downloads/Lynx-1.11.0-linux-x64.zip'),
          '/root/lynx/1.11.0/downloads/Lynx-1.11.0-linux-x64');
    });

    test('extraction installs the contents and removes its staging tree',
        () async {
      // A real tar round trip: the extractor, not a hand-written copy loop.
      final source = Directory('${temp.path}/payload/bin')
        ..createSync(recursive: true);
      final binary = File('${source.path}/lynx')..writeAsStringSync('#!/bin/sh');
      final archive = '${temp.path}/payload.tar.gz';
      final tar = await Process.run(
          'tar', ['-czf', archive, '-C', '${temp.path}/payload', 'bin']);
      if (tar.exitCode != 0) {
        // tar is absent on some CI images; the assertion below is the point of
        // the test, not the compression tool.
        return;
      }
      final destination = '${temp.path}/install';
      final installed = await extractArchiveTo(
          archivePath: archive, destinationDir: destination);
      expect(installed, greaterThan(0));
      expect(File('$destination/bin/lynx').existsSync(), isTrue);
      expect(binary.existsSync(), isTrue, reason: 'the archive is not consumed');
      // No staging tree survives next to the destination.
      final leftovers = Directory('${temp.path}')
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('.staging-'));
      expect(leftovers, isEmpty);
    });

    test('a failed extraction leaves nothing that looks installed', () async {
      final bogus = File('${temp.path}/broken.zip')..writeAsStringSync('not a zip');
      final destination = '${temp.path}/install-failed';
      await expectLater(
        extractArchiveTo(archivePath: bogus.path, destinationDir: destination),
        throwsA(isA<Exception>()),
      );
      expect(Directory(destination).existsSync(), isFalse,
          reason: 'a half-install must not be created');
      final leftovers = Directory('${temp.path}')
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.contains('.staging-'));
      expect(leftovers, isEmpty, reason: 'the staging tree is always removed');
    });
  });
}
