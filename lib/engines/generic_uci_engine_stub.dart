/// Platform-independent EngineProfile model.
/// Separated from generic_uci_engine.dart to avoid dart:io on web.

import 'dart:math';

/// Generates an identifier for a profile.
///
/// Profiles used to be identified by their position in the saved list, which
/// made every edit and delete a chance to point at the wrong engine: removing
/// one entry renumbered all the later ones, and the engine selected in
/// preferences kept referring to the old index. A stable id that is assigned
/// once, on creation, and survives reordering, editing and restarts is what
/// lets the rest of the app name an engine unambiguously — display names are
/// neither unique nor stable.
String newEngineProfileId() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final noise = Random().nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
  return '$now$noise';
}

/// A user-added UCI engine.
///
/// [name] is what the user sees (their own label if they typed one, otherwise
/// the engine's `id name`). [detectedName] keeps the engine-reported identity
/// even when the user renamed it, so two profiles for the same binary — or two
/// binaries that both call themselves "Stockfish" — stay distinguishable.
class EngineProfile {
  /// Stable identity of this profile. Never changes once assigned.
  final String id;

  /// Display name. Mutable: the user can rename, and a probe can fill it in.
  String name;
  String path;
  final Map<String, String> optionOverrides;

  /// Engine identity from the UCI handshake (`id name` / `id author`).
  String? detectedName;
  String? detectedAuthor;

  /// UCI options the engine advertised on the last successful handshake, in
  /// `"name=value"` form. Kept only so the manager can show what it found
  /// without re-probing; it is not a source of truth for behaviour.
  int optionCount;

  EngineProfile({
    String? id,
    required this.name,
    required this.path,
    Map<String, String>? optionOverrides,
    this.detectedName,
    this.detectedAuthor,
    this.optionCount = 0,
  })  : id = (id == null || id.isEmpty) ? newEngineProfileId() : id,
        optionOverrides = optionOverrides ?? {};

  /// The most useful name to show for this engine.
  String get displayName {
    if (name.trim().isNotEmpty) return name;
    if (detectedName != null && detectedName!.trim().isNotEmpty) {
      return detectedName!;
    }
    // Last resort: the binary name, better than an empty row.
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return slash >= 0 && slash + 1 < path.length ? path.substring(slash + 1) : path;
  }

  EngineProfile copyWith({
    String? name,
    String? path,
    Map<String, String>? optionOverrides,
    String? detectedName,
    String? detectedAuthor,
    int? optionCount,
  }) =>
      EngineProfile(
        id: id,
        name: name ?? this.name,
        path: path ?? this.path,
        optionOverrides: optionOverrides ?? Map.of(this.optionOverrides),
        detectedName: detectedName ?? this.detectedName,
        detectedAuthor: detectedAuthor ?? this.detectedAuthor,
        optionCount: optionCount ?? this.optionCount,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'path': path,
        'options': optionOverrides,
        if (detectedName != null) 'detectedName': detectedName,
        if (detectedAuthor != null) 'detectedAuthor': detectedAuthor,
        if (optionCount > 0) 'optionCount': optionCount,
      };

  /// Reads a saved profile, tolerating entries written by older versions.
  ///
  /// Older builds stored no `id` at all, so one is generated here; the store
  /// writes the migrated list back, which means the id becomes stable from the
  /// first run of this version onward. Missing or mistyped fields are defaulted
  /// rather than thrown on: a single corrupt entry used to make
  /// [profiles] throw and the whole Engine Manager screen fail to open.
  factory EngineProfile.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final rawOptions = json['options'];
    final overrides = <String, String>{};
    if (rawOptions is Map) {
      rawOptions.forEach((key, value) {
        if (value != null) overrides['$key'] = '$value';
      });
    }
    final rawCount = json['optionCount'];
    return EngineProfile(
      id: rawId is String && rawId.isNotEmpty ? rawId : null,
      name: json['name'] is String ? json['name'] as String : '',
      path: json['path'] is String ? json['path'] as String : '',
      optionOverrides: overrides,
      detectedName: json['detectedName'] is String
          ? json['detectedName'] as String
          : null,
      detectedAuthor: json['detectedAuthor'] is String
          ? json['detectedAuthor'] as String
          : null,
      optionCount: rawCount is int ? rawCount : 0,
    );
  }

  @override
  String toString() => 'EngineProfile($id, $name, $path)';
}
