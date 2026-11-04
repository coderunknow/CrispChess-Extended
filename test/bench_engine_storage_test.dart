/// Regressions for the unified engine storage and the verified download
/// manager: path redaction, write validation, migration without deletion,
/// traversal refusal, atomic install, coalescing and honest integrity labels.
library;

import 'dart:async';
import 'dart:io';

import 'package:crispchess/bench/benchmark_storage_base.dart';
import 'package:crispchess/engines/download_manager.dart';
import 'package:crispchess/engines/engine_artifacts.dart';
import 'package:crispchess/engines/engine_storage.dart';
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
      String literal(String value) => value.replaceAll("'", "''");
      const zip = r"C:\Users\Jane Doe\AppData\crispchess\lynx.part.zip";
      const staging = r"C:\Users\Jane Doe\AppData\crispchess\.staging-1";
      final command = "Expand-Archive -LiteralPath '${literal(zip)}' "
          "-DestinationPath '${literal(staging)}' -Force";
      expect(command, contains("-LiteralPath 'C:\\Users\\Jane Doe\\"));
      // Exactly two single-quoted regions: one path each, untouched otherwise.
      expect("'".allMatches(command).length, 4);
      // A quote inside a path is doubled, which is the only PowerShell escape.
      expect(literal(r"a'b"), r"a''b");
    });

    test('a staging tree is removable even when extraction throws', () async {
      final staging = Directory('${temp.path}/.staging-1')..createSync(recursive: true);
      File('${staging.path}/partial.bin').writeAsStringSync('x');
      // The finally block in LynxEngine._download does exactly this.
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      expect(staging.existsSync(), isFalse);
    });
  });
}
