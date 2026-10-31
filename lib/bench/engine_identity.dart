/// Stable identity for a benchmarked engine.
///
/// Every benchmark result is keyed by an [EngineIdentity], never by a display
/// name. The tournament code this replaces keyed standings and ratings by
/// `ChessEngine.name`, so two custom profiles called "Stockfish", or a profile
/// renamed between runs, silently merged or split their results — and a rating
/// list that merges two engines is not a rating list.
///
/// An identity carries what makes two measurements of "the same" engine
/// comparable:
///
///  * the stable engine id (`builtin:…` / `custom:<profileId>`, see
///    `lib/engines/engine_registry.dart`);
///  * the engine's *self-reported* name and version, which survive a rename;
///  * a fingerprint of the executable (SHA-256, cached against size+mtime) or,
///    for a built-in engine, the app build plus engine version;
///  * a digest of the configuration actually applied (option overrides);
///  * platform and execution backend, which decide whether two numbers may be
///    compared at all.
library;

import 'dart:convert' show utf8;

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../engines/generic_uci_engine_stub.dart' show EngineProfile;
import '../engines/engine_registry.dart'
    show customProfileIdFromId, isCustomEngineId, builtInNameFromId;
import 'benchmark_fingerprint.dart' show ExecutableStat;

/// Bumped when the content of a fingerprint changes meaning.
const int kFingerprintScheme = 1;

/// The platform this build is running on, in words a report can print.
String platformLabel() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'android';
    case TargetPlatform.iOS:
      return 'ios';
    case TargetPlatform.linux:
      return 'linux';
    case TargetPlatform.macOS:
      return 'macos';
    case TargetPlatform.windows:
      return 'windows';
    case TargetPlatform.fuchsia:
      return 'fuchsia';
  }
}

/// How a built-in engine actually executes on this platform.
///
/// Derived from the engine name because that is what the factory keys on; the
/// point is that a native FFI Stockfish and a browser WASM Stockfish must not
/// end up in one rating pool, and the report has to say which one it measured.
String backendForBuiltIn(String name) {
  final web = kIsWeb;
  switch (name) {
    case 'Built-in':
    case 'Maia3 Dart':
    case 'ChessMamba':
    case 'Ghost':
      return 'dart';
    case 'Stockfish':
      return web ? 'wasm' : 'native-process';
    case 'Frozenight':
      return web ? 'wasm' : 'ffi';
    case 'Lynx':
      return web ? 'wasm' : 'native-process';
    case 'Lc0':
      return web ? 'wasm' : 'ffi';
    default:
      // Searchless / language-model bots: Dart with an ONNX runtime.
      return name.startsWith('Searchless') ? 'dart-onnx' : 'dart';
  }
}

/// Backend label for a user-added UCI engine: always a spawned process.
const String kCustomBackend = 'native-process';

/// SHA-256 of [parts] joined with a separator that cannot occur in them.
String digestOf(Iterable<String> parts) {
  final joined = parts.join('\u0000');
  return crypto.sha256.convert(utf8.encode(joined)).toString();
}

/// A measured engine, as the benchmark knows it.
class EngineIdentity {
  /// Stable id: `builtin:<name>` or `custom:<profileId>`.
  final String engineId;

  /// Name shown to the user. Not unique, not stable — display only.
  final String displayName;

  /// Name the engine reports for itself (`id name`), or the built-in name.
  final String engineName;

  /// Version string: the engine's own when it reports one, otherwise the app
  /// build for built-ins, otherwise empty.
  final String engineVersion;

  /// Author, when the protocol reports one.
  final String? author;

  /// `builtin` or `custom`.
  final String kind;

  /// One of `android`, `ios`, `linux`, `macos`, `windows`, `web`.
  final String platform;

  /// `native-process`, `ffi`, `wasm`, `dart`, `dart-onnx`.
  final String backend;

  /// Binary SHA-256 for a native engine; a composite build identifier for a
  /// built-in one; `unavailable` when neither can be established.
  final String fingerprint;

  /// How [fingerprint] was obtained: `sha256`, `stat` (hash unavailable, size
  /// and mtime only — weak), `builtin-build`, or `unavailable`.
  final String fingerprintKind;

  /// Profile id of a user-added engine, so a report can be tied back to the
  /// profile without exporting its path.
  final String? profileId;

  /// Digest of the UCI options the engine advertised on the last handshake.
  final String? advertisedOptionsDigest;

  /// Number of options advertised, for context in the report.
  final int advertisedOptionCount;

  /// Digest of the option overrides actually applied before the first search.
  final String configurationDigest;

  /// The overrides themselves, so a report can say what they were.
  final Map<String, String> configuration;

  const EngineIdentity({
    required this.engineId,
    required this.displayName,
    required this.engineName,
    required this.engineVersion,
    this.author,
    required this.kind,
    required this.platform,
    required this.backend,
    required this.fingerprint,
    required this.fingerprintKind,
    this.profileId,
    this.advertisedOptionsDigest,
    this.advertisedOptionCount = 0,
    required this.configurationDigest,
    this.configuration = const {},
  });

  /// Identity of a built-in engine.
  ///
  /// [appBuild] is the application version, so an engine whose Dart source
  /// changed with the app gets a new fingerprint even when its own version
  /// string was not bumped.
  factory EngineIdentity.forBuiltIn({
    required String name,
    required String engineVersion,
    required String appBuild,
    Map<String, String> configuration = const {},
  }) {
    final platform = platformLabel();
    final backend = backendForBuiltIn(name);
    return EngineIdentity(
      engineId: 'builtin:$name',
      displayName: name,
      engineName: name,
      engineVersion: engineVersion,
      kind: 'builtin',
      platform: platform,
      backend: backend,
      fingerprint: 'builtin:$name@$appBuild+$engineVersion',
      fingerprintKind: 'builtin-build',
      configurationDigest: digestOf(
          configuration.entries.map((e) => '${e.key}=${e.value}').toList()
            ..sort()),
      configuration: Map.unmodifiable(configuration),
    );
  }

  /// Identity of a user-added UCI engine.
  ///
  /// [binarySha256] comes from the (cached) file hash; [stat] is the fallback
  /// when hashing failed, and produces a *weaker* fingerprint the report says
  /// so about.
  factory EngineIdentity.forCustom({
    required EngineProfile profile,
    required String? detectedName,
    required String? detectedAuthor,
    String? binarySha256,
    ExecutableStat? stat,
    Iterable<String>? advertisedOptions,
    Map<String, String> configuration = const {},
  }) {
    // Saved overrides are applied during initialization, before run options.
    final effectiveConfiguration = <String, String>{
      ...profile.optionOverrides,
      ...configuration,
    };
    final options = advertisedOptions?.toList();
    final String fingerprint;
    final String kind;
    if (binarySha256 != null && binarySha256.isNotEmpty) {
      fingerprint = 'sha256:$binarySha256';
      kind = 'sha256';
    } else if (stat != null) {
      fingerprint = 'stat:${stat.sizeBytes}:${stat.modifiedMillis}';
      kind = 'stat';
    } else {
      fingerprint = 'unavailable';
      kind = 'unavailable';
    }

    final selfName = (detectedName ?? '').trim();
    return EngineIdentity(
      engineId: 'custom:${profile.id}',
      displayName: profile.displayName,
      engineName: selfName.isEmpty ? profile.displayName : selfName,
      engineVersion: '',
      author: (detectedAuthor ?? '').trim().isEmpty ? null : detectedAuthor,
      kind: 'custom',
      platform: platformLabel(),
      backend: kCustomBackend,
      fingerprint: fingerprint,
      fingerprintKind: kind,
      profileId: profile.id,
      advertisedOptionsDigest:
          options == null ? null : digestOf(options.toList()..sort()),
      advertisedOptionCount: options?.length ?? 0,
      configurationDigest: digestOf(
          effectiveConfiguration.entries.map((e) => '${e.key}=${e.value}').toList()
            ..sort()),
      configuration: Map.unmodifiable(effectiveConfiguration),
    );
  }

  /// Identity re-derived with a different option configuration.
  EngineIdentity withConfiguration(Map<String, String> configuration) =>
      EngineIdentity(
        engineId: engineId,
        displayName: displayName,
        engineName: engineName,
        engineVersion: engineVersion,
        author: author,
        kind: kind,
        platform: platform,
        backend: backend,
        fingerprint: fingerprint,
        fingerprintKind: fingerprintKind,
        profileId: profileId,
        advertisedOptionsDigest: advertisedOptionsDigest,
        advertisedOptionCount: advertisedOptionCount,
        configurationDigest: digestOf(
            configuration.entries.map((e) => '${e.key}=${e.value}').toList()
              ..sort()),
        configuration: Map.unmodifiable(configuration),
      );

  /// Identity refined once the engine has advertised its options.
  EngineIdentity withAdvertisedOptions(List<String> optionNames) =>
      EngineIdentity(
        engineId: engineId,
        displayName: displayName,
        engineName: engineName,
        engineVersion: engineVersion,
        author: author,
        kind: kind,
        platform: platform,
        backend: backend,
        fingerprint: fingerprint,
        fingerprintKind: fingerprintKind,
        profileId: profileId,
        advertisedOptionsDigest:
            optionNames.isEmpty ? null : digestOf(optionNames.toList()..sort()),
        advertisedOptionCount: optionNames.length,
        configurationDigest: configurationDigest,
        configuration: configuration,
      );

  /// Identity refined once the engine has reported its own name/version.
  EngineIdentity withReportedIdentity({
    required String? name,
    required String? version,
    String? author,
  }) {
    final selfName = (name ?? '').trim();
    final selfVersion = (version ?? '').trim();
    return EngineIdentity(
      engineId: engineId,
      displayName: displayName,
      engineName: selfName.isEmpty ? engineName : selfName,
      engineVersion: selfVersion.isEmpty ? engineVersion : selfVersion,
      author: author ?? this.author,
      kind: kind,
      platform: platform,
      backend: backend,
      fingerprint: fingerprint,
      fingerprintKind: fingerprintKind,
      profileId: profileId,
      advertisedOptionsDigest: advertisedOptionsDigest,
      advertisedOptionCount: advertisedOptionCount,
      configurationDigest: configurationDigest,
      configuration: configuration,
    );
  }

  /// Key for game results, standings and ratings: the engine id.
  ///
  /// Kept separate from [identityKey] because a rating is about an engine, not
  /// about one of its configurations — the configuration is reported alongside.
  String get ratingKey => engineId;

  /// Key that also covers what was measured: engine, binary and configuration.
  /// Two runs whose identity keys differ are not the same measurement.
  String get identityKey =>
      '$engineId|$fingerprint|$configurationDigest|$platform/$backend';

  /// Grouping used to decide whether two measurements may share a rating pool.
  String get cohortKey => '$platform/$backend';

  /// First 12 hex characters of a SHA-256 fingerprint, for display.
  String get shortFingerprint {
    final value = fingerprint;
    final colon = value.indexOf(':');
    if (colon < 0) return value;
    final body = value.substring(colon + 1);
    return body.length <= 12 ? body : body.substring(0, 12);
  }

  /// Whether two identities describe the same binary/configuration, i.e. a
  /// re-benchmark is not needed.
  bool matchesVersionOf(EngineIdentity other) =>
      engineId == other.engineId &&
      fingerprint == other.fingerprint &&
      configurationDigest == other.configurationDigest &&
      backend == other.backend &&
      platform == other.platform;

  /// What the report shows as the engine, including version when known.
  String get label {
    if (engineVersion.isEmpty) return displayName;
    final lower = displayName.toLowerCase();
    if (lower.contains(engineVersion.toLowerCase())) return displayName;
    return '$displayName $engineVersion';
  }

  /// What makes this identity *materially* different from [other], for the
  /// version-change trigger. Null when nothing changed.
  String? changeFrom(EngineIdentity other) {
    if (engineId != other.engineId) return 'different engine';
    if (platform != other.platform) return 'platform changed';
    if (backend != other.backend) return 'execution backend changed';
    if (fingerprint != other.fingerprint) return 'binary changed';
    if (configurationDigest != other.configurationDigest) {
      return 'configuration changed';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'engineId': engineId,
        'displayName': displayName,
        'engineName': engineName,
        'engineVersion': engineVersion,
        if (author != null) 'author': author,
        'kind': kind,
        'platform': platform,
        'backend': backend,
        'fingerprint': fingerprint,
        'fingerprintKind': fingerprintKind,
        if (profileId != null) 'profileId': profileId,
        if (advertisedOptionsDigest != null)
          'advertisedOptionsDigest': advertisedOptionsDigest,
        'advertisedOptionCount': advertisedOptionCount,
        'configurationDigest': configurationDigest,
        if (configuration.isNotEmpty) 'configuration': configuration,
        'fingerprintScheme': kFingerprintScheme,
      };

  /// Reads a saved identity, defaulting anything missing: a report whose
  /// identity fields were written by an older schema must still load, with the
  /// gaps visible (`unknown`) rather than throwing.
  factory EngineIdentity.fromJson(Map<String, dynamic> json) {
    String str(String key, [String fallback = '']) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : fallback;
    }

    final config = <String, String>{};
    final rawConfig = json['configuration'];
    if (rawConfig is Map) {
      rawConfig.forEach((key, value) {
        if (value != null) config['$key'] = '$value';
      });
    }
    final engineId = str('engineId', 'unknown');
    final platform = str('platform', 'unknown');
    final backend = str('backend', 'unknown');
    return EngineIdentity(
      engineId: engineId,
      displayName: str('displayName', str('engineName', engineId)),
      engineName: str('engineName', engineId),
      engineVersion: str('engineVersion'),
      author: str('author').isEmpty ? null : str('author'),
      kind: str('kind', isCustomEngineId(engineId) ? 'custom' : 'builtin'),
      platform: platform,
      backend: backend,
      fingerprint: str('fingerprint', 'unavailable'),
      fingerprintKind: str('fingerprintKind', 'unavailable'),
      profileId: str('profileId').isEmpty
          ? customProfileIdFromId(engineId)
          : str('profileId'),
      advertisedOptionsDigest: str('advertisedOptionsDigest').isEmpty
          ? null
          : str('advertisedOptionsDigest'),
      advertisedOptionCount: json['advertisedOptionCount'] is num
          ? (json['advertisedOptionCount'] as num).toInt()
          : 0,
      configurationDigest: str('configurationDigest', 'unknown'),
      configuration: config,
    );
  }

  /// Built-in name behind this identity, when it is a built-in engine.
  String? get builtInName => builtInNameFromId(engineId);

  @override
  String toString() =>
      'EngineIdentity($engineId, $engineName, ${fingerprintKind.padRight(4)}$shortFingerprint, $cohortKey)';
}
