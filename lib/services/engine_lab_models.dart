import 'dart:convert';

import 'engine_match_service.dart';
import 'rating_fit.dart';

const int engineLabSchemaVersion = 1;

enum EngineBenchmarkPreset { quick, standard, accurate, custom }

class EngineBenchmarkConfig {
  final EngineBenchmarkPreset preset;
  final int timePerMoveMs;
  final int gamesPerPairing;
  final int maxGames;
  final int plyLimit;
  const EngineBenchmarkConfig({
    this.preset = EngineBenchmarkPreset.quick,
    this.timePerMoveMs = 100,
    this.gamesPerPairing = 2,
    this.maxGames = 120,
    this.plyLimit = 160,
  });

  static const Map<EngineBenchmarkPreset, int> defaults = {
    EngineBenchmarkPreset.quick: 100,
    EngineBenchmarkPreset.standard: 300,
    EngineBenchmarkPreset.accurate: 1000,
  };

  int estimatedGames(int engineCount) {
    if (engineCount < 2) return 0;
    return (engineCount * (engineCount - 1) ~/ 2) * gamesPerPairing;
  }

  List<String> validate(int engineCount) {
    final errors = <String>[];
    if (engineCount < 2) errors.add('Select at least two engines.');
    if (engineCount > 32) errors.add('Select no more than 32 engines per run.');
    if (timePerMoveMs < 10 || timePerMoveMs > 60000) {
      errors.add('Move time must be between 10 ms and 60,000 ms.');
    }
    if (gamesPerPairing < 2 || gamesPerPairing > 100 || gamesPerPairing.isOdd) {
      errors.add('Games per pairing must be an even number from 2 to 100 for color balance.');
    }
    if (maxGames < 1 || maxGames > 10000) errors.add('Game cap must be between 1 and 10,000.');
    if (estimatedGames(engineCount) > maxGames) {
      errors.add('Estimated ${estimatedGames(engineCount)} games exceeds the $maxGames game cap.');
    }
    if (plyLimit < 20 || plyLimit > 1000) errors.add('Ply limit must be between 20 and 1,000.');
    return errors;
  }

  Map<String, Object?> toJson() => {
        'preset': preset.name,
        'timePerMoveMs': timePerMoveMs,
        'gamesPerPairing': gamesPerPairing,
        'maxGames': maxGames,
        'plyLimit': plyLimit,
      };

  factory EngineBenchmarkConfig.fromJson(Map<String, dynamic> json) => EngineBenchmarkConfig(
        preset: EngineBenchmarkPreset.values.firstWhere(
          (value) => value.name == json['preset'],
          orElse: () => EngineBenchmarkPreset.custom,
        ),
        timePerMoveMs: json['timePerMoveMs'] as int? ?? 100,
        gamesPerPairing: json['gamesPerPairing'] as int? ?? 2,
        maxGames: json['maxGames'] as int? ?? 120,
        plyLimit: json['plyLimit'] as int? ?? 160,
      );
}

/// Redacts option values that might contain paths or credentials before a
/// report is exported. Safe tuning values (e.g. Threads and Hash) are kept.
String safeEngineOptionsDescription(Map<String, String> options) {
  const sensitive = ['path', 'file', 'dir', 'token', 'key', 'secret', 'password', 'credential', 'url', 'host'];
  return options.entries.map((entry) {
    final key = entry.key.trim();
    final lower = key.toLowerCase();
    final redact = sensitive.any((word) => lower.contains(word));
    return '$key=${redact ? '<redacted>' : entry.value}';
  }).join(', ');
}

class EngineBenchmarkIdentity {
  final String id;
  final String name;
  final String version;
  final String? detectedName;
  final String? author;
  final String implementation;
  final String optionsDescription;
  final String? binaryFingerprint;

  const EngineBenchmarkIdentity({
    required this.id,
    required this.name,
    required this.version,
    this.detectedName,
    this.author,
    required this.implementation,
    this.optionsDescription = '',
    this.binaryFingerprint,
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        if (detectedName != null) 'detectedName': detectedName,
        if (author != null) 'author': author,
        'implementation': implementation,
        'optionsDescription': optionsDescription,
        if (binaryFingerprint != null) 'binaryFingerprint': binaryFingerprint,
      };

  factory EngineBenchmarkIdentity.fromJson(Map<String, dynamic> json) => EngineBenchmarkIdentity(
        id: json['id'] as String,
        name: json['name'] as String,
        version: json['version'] as String? ?? 'unknown',
        detectedName: json['detectedName'] as String?,
        author: json['author'] as String?,
        implementation: json['implementation'] as String? ?? 'unknown',
        optionsDescription: json['optionsDescription'] as String? ?? '',
        binaryFingerprint: json['binaryFingerprint'] as String?,
      );
}

class EngineLatencyStats {
  final List<int> samplesMs;
  EngineLatencyStats(List<int> samples) : samplesMs = List.unmodifiable([...samples]..sort());

  int get count => samplesMs.length;
  int? get medianMs {
    if (samplesMs.isEmpty) return null;
    final middle = samplesMs.length ~/ 2;
    if (samplesMs.length.isOdd) return samplesMs[middle];
    return ((samplesMs[middle - 1] + samplesMs[middle]) / 2).round();
  }
  int? get p95Ms => _percentile(0.95);
  int? get p99Ms => _percentile(0.99);
  int? get maxMs => samplesMs.isEmpty ? null : samplesMs.last;

  int? _percentile(double percentile) => samplesMs.isEmpty
      ? null
      : samplesMs[(samplesMs.length * percentile)
          .ceil()
          .clamp(1, samplesMs.length)
          .toInt() - 1];
}

class EngineBenchmarkRun {
  final String id;
  final DateTime startedAt;
  final String platform;
  final String environment;
  final EngineBenchmarkConfig config;
  final List<EngineBenchmarkIdentity> engines;
  final List<GameResult> games;

  const EngineBenchmarkRun({
    required this.id,
    required this.startedAt,
    required this.platform,
    required this.environment,
    required this.config,
    required this.engines,
    required this.games,
  });

  int get completedGames => games.where((g) => g.eligibleForRating).length;
  int get forfeits => games.where((g) => g.status == GameResultStatus.forfeit).length;
  int get abortedGames => games.where((g) => g.status == GameResultStatus.aborted).length;
  int get cancelledGames => games.where((g) => g.status == GameResultStatus.cancelled).length;

  Map<String, EngineLatencyStats> get latencyByEngine {
    final values = <String, List<int>>{};
    for (final game in games) {
      values.putIfAbsent(game.whiteId, () => []).addAll(game.whiteMoveMillis);
      values.putIfAbsent(game.blackId, () => []).addAll(game.blackMoveMillis);
    }
    return {for (final entry in values.entries) entry.key: EngineLatencyStats(entry.value)};
  }

  bool get calibratedEloAvailable => false;
  String get calibrationNote =>
      'Unavailable: no reference set matched to this engine version, hardware, implementation and move budget.';

  List<PlayerRating> get ratings => fitRatings([
        for (final game in games)
          if (game.eligibleForRating)
            (white: game.whiteId, black: game.blackId, score: game.whiteScore),
      ]);

  Map<String, Object?> toJson() => {
        'schemaVersion': engineLabSchemaVersion,
        'id': id,
        'startedAt': startedAt.toUtc().toIso8601String(),
        'platform': platform,
        'environment': environment,
        'config': config.toJson(),
        'engines': engines.map((e) => e.toJson()).toList(),
        'games': games.map(_gameToJson).toList(),
        'calibratedElo': null,
      };

  factory EngineBenchmarkRun.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != engineLabSchemaVersion) {
      throw FormatException('Unsupported benchmark report schema ${json['schemaVersion']}');
    }
    final config = EngineBenchmarkConfig.fromJson(
        Map<String, dynamic>.from(json['config'] as Map));
    final engines = (json['engines'] as List)
        .map((e) => EngineBenchmarkIdentity.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (engines.length < 2 || engines.any((e) => e.id.isEmpty || e.name.isEmpty) ||
        engines.map((e) => e.id).toSet().length != engines.length) {
      throw const FormatException('A benchmark report needs at least two uniquely identified engines');
    }
    final configErrors = config.validate(engines.length);
    if (configErrors.isNotEmpty) {
      throw FormatException('Invalid benchmark configuration: ${configErrors.join('; ')}');
    }
    final games = (json['games'] as List)
        .map((e) => _gameFromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    if (games.length > config.maxGames) {
      throw const FormatException('Benchmark report exceeds its declared game cap');
    }
    final ids = engines.map((e) => e.id).toSet();
    for (final game in games) {
      if (!ids.contains(game.whiteId) || !ids.contains(game.blackId)) {
        throw const FormatException('Benchmark game refers to an unknown engine identity');
      }
    }
    return EngineBenchmarkRun(
      id: json['id'] as String,
      startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
      platform: json['platform'] as String? ?? 'unknown',
      environment: json['environment'] as String? ?? 'unknown',
      config: config,
      engines: engines,
      games: games,
    );
  }

  String toJsonText() => const JsonEncoder.withIndent('  ').convert(toJson());

  static String toCsv(List<EngineBenchmarkRun> runs) {
    final out = StringBuffer('run_id,started_at,engine_id,engine,relative_elo,std_error,ci95_low,ci95_high,games,wins,draws,losses,score_percent,latency_samples,median_move_ms,p95_move_ms,p99_move_ms,max_move_ms,platform,time_per_move_ms\n');
    for (final run in runs) {
      for (final rating in run.ratings) {
        final engine = run.engines.firstWhere((e) => e.id == rating.name);
        final latency = run.latencyByEngine[rating.name];
        final values = [
          _csvSafeCell(run.id),
          run.startedAt.toUtc().toIso8601String(),
          _csvSafeCell(engine.id),
          _csvSafeCell(engine.name),
          rating.rating.toStringAsFixed(1),
          rating.stdErr.isFinite ? rating.stdErr.toStringAsFixed(1) : '',
          rating.stdErr.isFinite ? rating.ci95Low.toStringAsFixed(1) : '',
          rating.stdErr.isFinite ? rating.ci95High.toStringAsFixed(1) : '',
          rating.games,
          rating.wins,
          rating.draws,
          rating.losses,
          (rating.score * 100).toStringAsFixed(1),
          latency?.count ?? 0,
          latency?.medianMs ?? '',
          latency?.p95Ms ?? '',
          latency?.p99Ms ?? '',
          latency?.maxMs ?? '',
          _csvSafeCell(run.platform),
          run.config.timePerMoveMs,
        ].map(_csv).join(',');
        out.writeln(values);
      }
    }
    return out.toString();
  }
}

Map<String, Object?> _gameToJson(GameResult game) => {
      'white': game.white,
      'black': game.black,
      'whiteId': game.whiteId,
      'blackId': game.blackId,
      'result': game.result,
      'moves': game.moves,
      'pgn': game.pgn,
      'whiteMoveMillis': game.whiteMoveMillis,
      'blackMoveMillis': game.blackMoveMillis,
      'status': game.status.name,
      if (game.failureReason != null) 'failureReason': game.failureReason,
    };

GameResult _gameFromJson(Map<String, dynamic> json) {
  final result = json['result'] as String;
  if (!const {'1-0', '0-1', '1/2-1/2'}.contains(result)) {
    throw const FormatException('Invalid game result token');
  }
  final statusName = json['status'] as String? ?? 'completed';
  final status = GameResultStatus.values.where((s) => s.name == statusName).firstOrNull;
  if (status == null) throw FormatException('Unknown game result status "$statusName"');
  final white = json['white'] as String;
  final black = json['black'] as String;
  final whiteId = json['whiteId'] as String? ?? white;
  final blackId = json['blackId'] as String? ?? black;
  final moves = json['moves'] as int;
  final whiteTimes = (json['whiteMoveMillis'] as List? ?? const []).cast<int>();
  final blackTimes = (json['blackMoveMillis'] as List? ?? const []).cast<int>();
  if (whiteTimes.any((time) => time < 0) || blackTimes.any((time) => time < 0)) {
    throw const FormatException('Invalid engine latency sample');
  }
  if (whiteId.isEmpty || blackId.isEmpty || whiteId == blackId || moves < 0) {
    throw const FormatException('Invalid game participant identity or move count');
  }
  return GameResult(
    white: white,
    black: black,
    whiteId: whiteId,
    blackId: blackId,
    result: result,
    moves: moves,
    pgn: json['pgn'] as String? ?? '',
    whiteMoveMillis: List.unmodifiable(whiteTimes),
    blackMoveMillis: List.unmodifiable(blackTimes),
    status: status,
    failureReason: json['failureReason'] as String?,
  );
}

String _csvSafeCell(String text) =>
    RegExp(r'^[\s]*[=+@-]').hasMatch(text) ? "'$text" : text;

String _csv(Object value) {
  final text = '$value';
  return '"${text.replaceAll('"', '""')}"';
}
