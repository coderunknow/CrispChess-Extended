/// Calibrated Elo: a relative rating re-expressed on a published scale.
///
/// The relative rating this app computes is centred on 1500 by convention. That
/// is a *relative* scale: it orders the engines in one run and says nothing
/// about how strong they are in absolute terms. Turning it into a number that
/// can be compared with a published engine rating needs a **declared anchor** —
/// an engine that took part in the run and whose rating on that scale has been
/// published together with the conditions it was measured under.
///
/// Three things follow from that, and this file enforces all three:
///
///  1. No anchor in the run ⇒ calibrated Elo is **unavailable**. Inventing one
///     (say, "Stockfish is 3600") would produce a confident wrong number.
///  2. The anchor's measurement conditions have to match the run's: a published
///     rating at 40 moves in 2 minutes on one core does not transfer to a
///     100 ms-per-move benchmark on a phone.
///  3. An anchor that is itself uncertain, or that sits on a different platform
///     or backend than the other engines, cannot calibrate anything.
///
/// The app therefore ships **no** built-in anchor numbers. The user supplies
/// one (Engine Lab → Calibration), with the source it came from, and the report
/// records it so anyone reading the result can judge whether it applies.
library;

import 'benchmark_config.dart';
import 'elo.dart';
import 'engine_identity.dart';

/// A published rating for one engine, with the conditions it was measured
/// under.
class RatingAnchor {
  /// Stable id for the stored anchor (generated on creation).
  final String id;

  /// The engine this rating belongs to, as the benchmark names it: either the
  /// exact engine id, or the engine's self-reported/display name.
  final String engineName;

  /// Exact engine id (`builtin:Stockfish`, `custom:<profileId>`), when known.
  /// Takes precedence over [engineName].
  final String? engineIdHint;

  /// Version the published rating refers to ("17", "11", "0.31.2").
  final String engineVersion;

  /// The published rating on [scale].
  final double rating;

  /// Which rating list or scale it is ("CCRL 40/2", "CEGT 40/20", "custom").
  final String scale;

  /// Where the number comes from: a URL, a publication, a date-stamped table.
  final String source;

  /// When it was published or measured (ISO-8601 date, `YYYY-MM-DD`).
  final String publishedDate;

  /// Hardware the reference measurement used.
  final String hardware;

  /// Time control or move budget, in the list's own words.
  final String timeControl;

  /// The same budget in milliseconds per move, when the list specifies one.
  /// Used to check the anchor against this run's budget.
  final int? timePerMoveMs;

  /// How far the run's budget may differ from [timePerMoveMs] and still be
  /// considered comparable. 20% by default.
  final int tolerancePercent;

  final String notes;

  const RatingAnchor({
    required this.id,
    required this.engineName,
    this.engineIdHint,
    this.engineVersion = '',
    required this.rating,
    required this.scale,
    required this.source,
    required this.publishedDate,
    required this.hardware,
    required this.timeControl,
    this.timePerMoveMs,
    this.tolerancePercent = 20,
    this.notes = '',
  });

  /// Whether every field a defensible calibration needs is filled in.
  bool get isComplete =>
      engineName.trim().isNotEmpty &&
      rating.isFinite &&
      scale.trim().isNotEmpty &&
      source.trim().isNotEmpty &&
      publishedDate.trim().isNotEmpty &&
      hardware.trim().isNotEmpty &&
      timeControl.trim().isNotEmpty;

  /// The fields that are missing, for the UI to point at.
  List<String> get missingFields => [
        if (engineName.trim().isEmpty) 'engine',
        if (!rating.isFinite) 'rating',
        if (scale.trim().isNotEmpty == false) 'scale',
        if (source.trim().isEmpty) 'source',
        if (publishedDate.trim().isEmpty) 'published date',
        if (hardware.trim().isEmpty) 'hardware',
        if (timeControl.trim().isEmpty) 'time control',
      ];

  Map<String, dynamic> toJson() => {
        'id': id,
        'engineName': engineName,
        if (engineIdHint != null) 'engineId': engineIdHint,
        'engineVersion': engineVersion,
        'rating': rating,
        'scale': scale,
        'source': source,
        'publishedDate': publishedDate,
        'hardware': hardware,
        'timeControl': timeControl,
        if (timePerMoveMs != null) 'timePerMoveMs': timePerMoveMs,
        'tolerancePercent': tolerancePercent,
        if (notes.isNotEmpty) 'notes': notes,
      };

  factory RatingAnchor.fromJson(Map<String, dynamic> json) {
    double doubleOf(String key, [double fallback = 0]) {
      final value = json[key];
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? fallback;
      return fallback;
    }

    int? intOf(String key) {
      final value = json[key];
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return RatingAnchor(
      id: (json['id'] as String?) ?? 'anchor',
      engineName: (json['engineName'] as String?) ?? '',
      engineIdHint: json['engineId'] as String?,
      engineVersion: (json['engineVersion'] as String?) ?? '',
      rating: doubleOf('rating'),
      scale: (json['scale'] as String?) ?? '',
      source: (json['source'] as String?) ?? '',
      publishedDate: (json['publishedDate'] as String?) ?? '',
      hardware: (json['hardware'] as String?) ?? '',
      timeControl: (json['timeControl'] as String?) ?? '',
      timePerMoveMs: intOf('timePerMoveMs'),
      tolerancePercent: intOf('tolerancePercent') ?? 20,
      notes: (json['notes'] as String?) ?? '',
    );
  }

  /// One line for a list.
  String get label =>
      '$engineName${engineVersion.isEmpty ? '' : ' $engineVersion'}'
      ' · ${rating.toStringAsFixed(0)} ($scale)';
}

/// The outcome of trying to calibrate a fit.
class CalibrationOutcome {
  final bool available;

  /// Why calibration is unavailable, or a description of the anchor used.
  final String reason;

  /// Added to every relative rating to reach the calibrated scale.
  final double? offset;

  /// The engine whose published rating defined the offset.
  final String? anchorEngineId;
  final String? anchorLabel;

  /// Calibrated rating per engine id. Empty when unavailable.
  final Map<String, double> calibrated;

  final List<String> warnings;

  const CalibrationOutcome({
    required this.available,
    required this.reason,
    this.offset,
    this.anchorEngineId,
    this.anchorLabel,
    this.calibrated = const {},
    this.warnings = const [],
  });

  factory CalibrationOutcome.unavailable(String reason,
          {List<String> warnings = const []}) =>
      CalibrationOutcome(
        available: false,
        reason: reason,
        warnings: warnings,
      );

  double? ratingFor(String engineId) => calibrated[engineId];

  Map<String, dynamic> toJson() => {
        'available': available,
        'reason': reason,
        if (offset != null) 'offset': offset,
        if (anchorEngineId != null) 'anchorEngineId': anchorEngineId,
        if (anchorLabel != null) 'anchorLabel': anchorLabel,
        if (calibrated.isNotEmpty) 'calibrated': calibrated,
        if (warnings.isNotEmpty) 'warnings': warnings,
      };

  factory CalibrationOutcome.fromJson(Map<String, dynamic> json) {
    final calibrated = <String, double>{};
    final raw = json['calibrated'];
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is num) calibrated['$key'] = value.toDouble();
      });
    }
    final warnings = <String>[];
    final rawWarnings = json['warnings'];
    if (rawWarnings is List) {
      for (final warning in rawWarnings) {
        warnings.add('$warning');
      }
    }
    final offset = json['offset'];
    return CalibrationOutcome(
      available: json['available'] == true,
      reason: (json['reason'] as String?) ?? '',
      offset: offset is num ? offset.toDouble() : null,
      anchorEngineId: json['anchorEngineId'] as String?,
      anchorLabel: json['anchorLabel'] as String?,
      calibrated: calibrated,
      warnings: warnings,
    );
  }
}

/// Re-expresses [fit] on the scale of [anchor].
///
/// [identities] is the set of engines that took part; it is used to decide
/// whether the run is one comparable cohort and to find the anchor.
CalibrationOutcome calibrateElo({
  required EloFit fit,
  required RatingAnchor? anchor,
  required BenchmarkConfig config,
  required List<EngineIdentity> identities,
}) {
  if (anchor == null) {
    return CalibrationOutcome.unavailable(
        'No calibration anchor is declared. Relative Elo only.');
  }
  if (!anchor.isComplete) {
    return CalibrationOutcome.unavailable(
        'The calibration anchor is incomplete (missing: '
        '${anchor.missingFields.join(', ')}).');
  }

  final anchorRating = _findAnchorRating(fit, anchor);
  if (anchorRating == null) {
    return CalibrationOutcome.unavailable(
        '"${anchor.engineName}" did not take part in this benchmark, so there '
        'is no bridge from the relative scale to ${anchor.scale}.');
  }
  if (anchorRating.stdErr.isInfinite || anchorRating.stdErr > 100) {
    return CalibrationOutcome.unavailable(
        'The anchor engine\'s own rating in this run is too uncertain '
        '(±${(kZ95 * anchorRating.stdErr).toStringAsFixed(0)} Elo) to carry a '
        'published number across.');
  }


  if (fit.components.length != 1) {
    return CalibrationOutcome.unavailable('Disconnected rating pools cannot share an anchor.');
  }
  if (!config.isTimeBased) {
    return CalibrationOutcome.unavailable('A time-control anchor cannot calibrate a depth or node budget.');
  }
  final warnings = <String>[];
  final anchorBudget = anchor.timePerMoveMs;
  if (anchorBudget == null) {
    return CalibrationOutcome.unavailable('The anchor must state a positive move budget.');
  } else if (anchorBudget <= 0 || anchor.tolerancePercent < 0 || anchor.tolerancePercent > 100) {
    return CalibrationOutcome.unavailable('Invalid anchor budget or tolerance.');
  } else if (config.isTimeBased) {
    final runBudget = config.timePerMove.inMilliseconds;
    final deviationPercent =
        (runBudget - anchorBudget).abs() * 100 / anchorBudget;
    if (deviationPercent > anchor.tolerancePercent) {
      return CalibrationOutcome.unavailable(
          'The anchor was measured at ${anchor.timeControl} '
          '(${anchorBudget} ms/move) and this run used ${runBudget} ms/move, a '
          '${deviationPercent.toStringAsFixed(0)}% difference — beyond the '
          '${anchor.tolerancePercent}% this anchor allows.');
    }
    warnings.add('This run used ${runBudget} ms/move against the anchor\'s '
        '${anchor.timeControl}; within the tolerance, but not identical.');
  } else {
    warnings.add('This run used a fixed depth (${config.searchDepth}), whose '
        'cost in time differs between engines; the calibrated scale is '
        'approximate.');
  }
  final anchorIdentities = identities.where((identity) =>
      identity.engineId == anchorRating.engineId).toList();
  if (anchor.engineVersion.trim().isEmpty || anchorIdentities.length != 1 ||
      anchorIdentities.single.engineVersion != anchor.engineVersion.trim()) {
    return CalibrationOutcome.unavailable('The anchor version must match the measured engine version.');
  }
  // Refuse a mixed-platform run only once the anchor is known to be here and
  // comparable: "the anchor did not take part" is the actionable answer when
  // that is the problem, and a cohort warning would bury it. A run that mixes
  // platforms still never produces a published number.
  final cohorts = <String>{for (final identity in identities) identity.cohortKey};
  if (cohorts.length > 1) {
    return CalibrationOutcome.unavailable(
        'The run mixes ${cohorts.length} cohorts (${cohorts.join(', ')}); a '
        'published rating cannot be transferred across platforms or backends.');
  }
  warnings.add('A published rating is a measurement of a specific engine '
      'version on specific hardware. The anchor used here was '
      '${anchor.engineVersion.isEmpty ? 'of unspecified version' : 'version ${anchor.engineVersion}'} '
      'on ${anchor.hardware}, published ${anchor.publishedDate} '
      '(${anchor.source}).');

  final offset = anchor.rating - anchorRating.rating;
  final calibrated = <String, double>{
    for (final rating in fit.ratings) rating.engineId: rating.rating + offset,
  };
  return CalibrationOutcome(
    available: true,
    reason: 'Calibrated against ${anchor.engineName} at ${anchor.rating} '
        '(${anchor.scale}), offset ${offset.toStringAsFixed(1)} Elo.',
    offset: offset,
    anchorEngineId: anchorRating.engineId,
    anchorLabel: anchorRating.label,
    calibrated: calibrated,
    warnings: warnings,
  );
}

EloRating? _findAnchorRating(EloFit fit, RatingAnchor anchor) {
  final hint = anchor.engineIdHint;
  if (hint != null && hint.isNotEmpty) return fit.ratingFor(hint);
  final wanted = anchor.engineName.trim().toLowerCase();
  final matches = fit.ratings.where((rating) =>
      rating.label.trim().toLowerCase() == wanted).toList();
  return matches.length == 1 ? matches.single : null;
}

/// Documentation shown next to the calibration form: what makes an anchor
/// defensible.
const List<String> kAnchorRequirements = [
  'Name the engine version the published rating refers to.',
  'Record where the number comes from (rating list, publication, URL) and '
      'when it was measured.',
  'Record the hardware and the time control or move budget it was measured '
      'under.',
  'The anchor engine has to take part in this benchmark: without it there is '
      'no bridge to the published scale.',
  'Puzzle ratings, advertised strength, estimated metadata Elo and human '
      'playing strength are not engine-versus-engine ratings and cannot be used '
      'as an anchor.',
];
