/// Engine Lab preferences and the policy for benchmarks that start themselves.
///
/// Kept apart from the app's [PreferencesService] on purpose: the Lab's keys are
/// namespaced (`lab.*`), the values are structured (a config, a set of rating
/// anchors, opening suites), and a settings screen that grows a bad key must not
/// be able to break the game screen's preferences.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'benchmark_config.dart';
import 'calibration.dart';
import 'opening_suite.dart';

/// What may start a benchmark without the user asking for one.
///
/// Automatic runs are deliberately capped: an "automatic" benchmark that costs
/// an hour of battery is not a courtesy. These limits are enforced by building
/// the config here rather than by trusting the caller.
class AutoBenchmarkSettings {
  /// Run a quick benchmark when a new engine is added.
  final bool afterAdd;

  /// Re-run when an engine's binary or configuration changed.
  final bool afterVersionChange;

  /// Hard cap on games for an automatic run.
  final int maxGames;

  /// Hard cap on wall-clock time for an automatic run.
  final Duration maxDuration;

  const AutoBenchmarkSettings({
    this.afterAdd = true,
    this.afterVersionChange = true,
    this.maxGames = 24,
    this.maxDuration = const Duration(minutes: 10),
  });

  /// The config an automatic run uses: the Quick preset, capped, with no
  /// warm-up games (a warm-up is 10% of a 20-game run and buys nothing on a
  /// run this short), and a fresh seed so two automatic runs are not the same
  /// game over again.
  BenchmarkConfig toConfig({int seed = 1}) => BenchmarkConfig.quick.copyWith(
        // `copyWith` takes a factory for the nullable fields so it can clear
        // them; passing the value itself does not compile.
        maxGames: () => maxGames.clamp(2, 24).toInt(),
        maxDuration: () => maxDuration > const Duration(minutes: 10)
            ? const Duration(minutes: 10) : maxDuration,
        warmUpGames: 0,
        seed: seed,
        adaptiveStopping: true,
        // One repetition: an automatic run is a sanity check, not a measurement
        // programme, and the cap above is expressed in games.
        repetitions: 1,
      );

  AutoBenchmarkSettings copyWith({
    bool? afterAdd,
    bool? afterVersionChange,
    int? maxGames,
    Duration? maxDuration,
  }) =>
      AutoBenchmarkSettings(
        afterAdd: afterAdd ?? this.afterAdd,
        afterVersionChange: afterVersionChange ?? this.afterVersionChange,
        maxGames: maxGames ?? this.maxGames,
        maxDuration: maxDuration ?? this.maxDuration,
      );

  Map<String, dynamic> toJson() => {
        'afterAdd': afterAdd,
        'afterVersionChange': afterVersionChange,
        'maxGames': maxGames,
        'maxDurationMinutes': maxDuration.inMinutes,
      };

  factory AutoBenchmarkSettings.fromJson(Map<String, dynamic> json) {
    final maxGames = json['maxGames'];
    final maxMinutes = json['maxDurationMinutes'];
    return AutoBenchmarkSettings(
      afterAdd: json['afterAdd'] is bool ? json['afterAdd'] as bool : true,
      afterVersionChange: json['afterVersionChange'] is bool
          ? json['afterVersionChange'] as bool
          : true,
      maxGames: maxGames is num ? maxGames.toInt().clamp(2, 24).toInt() : 24,
      maxDuration: maxMinutes is num
          ? Duration(minutes: maxMinutes.toInt().clamp(1, 10).toInt())
          : const Duration(minutes: 10),
    );
  }
}

/// Persisted Engine Lab state: last configuration, anchors, opening suites and
/// the automatic-run policy.
class BenchmarkSettingsStore {
  static const _keyAuto = 'lab.auto';
  static const _keyLastConfig = 'lab.lastConfig';
  static const _keyLastEngineIds = 'lab.lastEngineIds';
  static const _keyAnchors = 'lab.anchors';
  static const _keySuites = 'lab.suites';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<SharedPreferences> _instance() async {
    await init();
    return _prefs!;
  }

  Future<AutoBenchmarkSettings> autoSettings() async {
    final prefs = await _instance();
    final raw = prefs.getString(_keyAuto);
    if (raw == null || raw.isEmpty) return const AutoBenchmarkSettings();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return AutoBenchmarkSettings.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (error) {
      debugPrint('[EngineLab] unreadable automatic-run settings: $error');
    }
    return const AutoBenchmarkSettings();
  }

  Future<void> setAutoSettings(AutoBenchmarkSettings settings) async {
    final prefs = await _instance();
    await prefs.setString(_keyAuto, jsonEncode(settings.toJson()));
  }

  Future<BenchmarkConfig> lastConfig() async {
    final prefs = await _instance();
    final raw = prefs.getString(_keyLastConfig);
    if (raw == null || raw.isEmpty) return BenchmarkConfig.standard;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final config = BenchmarkConfig.fromJson(Map<String, dynamic>.from(decoded));
        // A stored configuration that no longer validates is worse than no
        // stored configuration: fall back rather than fail at the last step.
        final validation = validateConfig(config, engineCount: 2);
        if (validation.isValid) return config;
        debugPrint('[EngineLab] stored config no longer valid: '
            '${validation.errors.join(' ')}');
      }
    } catch (error) {
      debugPrint('[EngineLab] unreadable stored config: $error');
    }
    return BenchmarkConfig.standard;
  }

  Future<void> setLastConfig(BenchmarkConfig config) async {
    final prefs = await _instance();
    await prefs.setString(_keyLastConfig, jsonEncode(config.toJson()));
  }

  Future<List<String>> lastEngineIds() async {
    final prefs = await _instance();
    return prefs.getStringList(_keyLastEngineIds) ?? const [];
  }

  Future<void> setLastEngineIds(List<String> ids) async {
    final prefs = await _instance();
    await prefs.setStringList(_keyLastEngineIds, ids);
  }

  Future<List<RatingAnchor>> anchors() async {
    final prefs = await _instance();
    final raw = prefs.getString(_keyAnchors);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [
          for (final entry in decoded)
            if (entry is Map)
              RatingAnchor.fromJson(Map<String, dynamic>.from(entry)),
        ];
      }
    } catch (error) {
      debugPrint('[EngineLab] unreadable rating anchors: $error');
    }
    return const [];
  }

  Future<void> setAnchors(List<RatingAnchor> anchors) async {
    final prefs = await _instance();
    await prefs.setString(
      _keyAnchors,
      jsonEncode([for (final anchor in anchors) anchor.toJson()]),
    );
  }

  /// Opening suites the user added. Built-in suites are not stored.
  Future<Map<String, OpeningSuite>> openingSuites() async {
    final prefs = await _instance();
    final raw = prefs.getString(_keySuites);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final suites = <String, OpeningSuite>{};
        for (final entry in decoded) {
          if (entry is! Map) continue;
          final suite = OpeningSuite.fromJson(Map<String, dynamic>.from(entry));
          suites[suite.id] = suite;
        }
        return suites;
      }
    } catch (error) {
      debugPrint('[EngineLab] unreadable opening suites: $error');
    }
    return const {};
  }

  Future<void> setOpeningSuites(Map<String, OpeningSuite> suites) async {
    final prefs = await _instance();
    await prefs.setString(
      _keySuites,
      jsonEncode([for (final suite in suites.values) suite.toJson()]),
    );
  }
}
