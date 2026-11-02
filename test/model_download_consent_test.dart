// Model engines download their networks during initialize(). Engine
// Preflight asks for consent first, which only works if the engine says what
// it would download (DownloadAwareEngine) — without downloading anything to
// find out. These tests never touch the network: they compare each adapter's
// answer with the model cache, whatever state that cache is in.
@TestOn('vm')
library;

import 'package:crispchess/engines/chessmamba_engine.dart';
import 'package:crispchess/engines/engine_initialization.dart';
import 'package:crispchess/engines/ghost_engine.dart';
import 'package:crispchess/engines/maia3_dart/onnx/model_fetch.dart';
import 'package:crispchess/engines/maia3_dart/variants.dart';
import 'package:crispchess/engines/maia3_dart_engine.dart';
import 'package:crispchess/engines/model_download.dart';
import 'package:crispchess/engines/searchless_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a model that is not cached is reported, with its source', () async {
    const url = 'https://example.invalid/preflight/never-cached.onnx';
    final requirement = await pendingModelDownload(
      description: 'test model',
      files: [(url, 'crispchess_preflight_never_cached.onnx')],
      license: 'MIT',
    );
    expect(requirement, isNotNull);
    expect(requirement!.source, Uri.parse(url));
    expect(requirement.bytes, isNull, reason: 'sizes are never estimated');
    expect(requirement.license, 'MIT');
  });

  test('model engines declare what they would download', () async {
    expect(ChessMambaEngine(), isA<DownloadAwareEngine>());
    expect(Maia3DartEngine(), isA<DownloadAwareEngine>());
    expect(GhostEngine(), isA<DownloadAwareEngine>());
    expect(SearchlessEngine(SearchlessSize.m9), isA<DownloadAwareEngine>());
  });

  test('ChessMamba reports its model exactly when it is not cached', () async {
    final cached = await isModelCached(
        chessMambaModelUrl, 'chessmamba_step_batch.onnx');
    final requirement = await ChessMambaEngine().pendingDownload();
    expect(requirement == null, cached);
    if (requirement != null) {
      expect(requirement.source, Uri.parse(chessMambaModelUrl));
    }
  });

  test('Maia3 and Ghost report the Maia3 model exactly when not cached',
      () async {
    final variant = getVariant('5m');
    final cached = await isModelCached(variant.url, variant.onnxFile);
    final maia = await Maia3DartEngine(variantId: '5m').pendingDownload();
    final ghost = await GhostEngine().pendingDownload();
    expect(maia == null, cached);
    expect(ghost == null, cached);
    if (maia != null) expect(maia.source, Uri.parse(variant.url));
    if (ghost != null) expect(ghost.source, Uri.parse(variant.url));
  });

  test('injected models download nothing', () async {
    expect(
        await ChessMambaEngine(
                modelFactory: () async => throw UnimplementedError())
            .pendingDownload(),
        isNull);
    expect(
        await SearchlessEngine(SearchlessSize.m9,
                loader: () async => throw UnimplementedError())
            .pendingDownload(),
        isNull);
    expect(
        await GhostEngine(policyOverride: (position, elo) async => {})
            .pendingDownload(),
        isNull);
  });
}
