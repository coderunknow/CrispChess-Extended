/// One structured diagnostic entry.
///
/// Records are structured rather than `debugPrint` text so the in-app viewer
/// can filter by severity and component, and the export can separate errors
/// from lifecycle events without parsing prose (dev6).
library;

/// Severity of a diagnostic entry, ordered so levels can be filtered by
/// "at least".
enum DiagLevel {
  trace,
  debug,
  info,
  warning,
  error,
  fatal;

  /// Upper-case name used in UI chips and exported files.
  String get label {
    switch (this) {
      case DiagLevel.trace: return 'TRACE';
      case DiagLevel.debug: return 'DEBUG';
      case DiagLevel.info: return 'INFO';
      case DiagLevel.warning: return 'WARNING';
      case DiagLevel.error: return 'ERROR';
      case DiagLevel.fatal: return 'FATAL';
    }
  }

  static DiagLevel fromLabel(String label) {
    for (final level in DiagLevel.values) {
      if (level.label == label.toUpperCase() || level.name == label.toLowerCase()) {
        return level;
      }
    }
    return DiagLevel.info;
  }
}

/// A single structured log record.
class DiagLogRecord {
  final DateTime timestamp;
  final DiagLevel level;

  /// The subsystem that produced the entry, e.g. `engine`, `benchmark`,
  /// `ui.engineManager`, `flutter`.
  final String component;

  /// A short stable event name, e.g. `process.started`, `handshake.failed`.
  final String event;

  final String? message;

  /// Id of the app session, shared by every entry of one launch.
  final String sessionId;

  /// Monotonic per-session counter that groups related entries.
  final int correlationId;

  /// Engine profile the entry is about, when there is one.
  final String? profileId;

  /// How long the logged operation took, when it is one.
  final int? durationMs;

  final String? error;
  final String? stackTrace;

  /// A few extra key/value pairs. Kept small on purpose: a log entry is not a
  /// place to dump object state.
  final Map<String, String> fields;

  const DiagLogRecord({
    required this.timestamp,
    required this.level,
    required this.component,
    required this.event,
    this.message,
    required this.sessionId,
    required this.correlationId,
    this.profileId,
    this.durationMs,
    this.error,
    this.stackTrace,
    this.fields = const {},
  });

  Map<String, dynamic> toJson() => {
        'ts': timestamp.toUtc().toIso8601String(),
        'level': level.label,
        'component': component,
        'event': event,
        if (message != null) 'message': message,
        'session': sessionId,
        'correlation': correlationId,
        if (profileId != null) 'profileId': profileId,
        if (durationMs != null) 'durationMs': durationMs,
        if (error != null) 'error': error,
        if (stackTrace != null) 'stackTrace': stackTrace,
        if (fields.isNotEmpty) 'fields': fields,
      };

  static DiagLogRecord fromJson(Map<String, dynamic> json) {
    final timestampRaw = json['ts'];
    return DiagLogRecord(
      timestamp: timestampRaw is String
          ? DateTime.tryParse(timestampRaw)?.toLocal() ?? DateTime.now()
          : DateTime.now(),
      level: DiagLevel.fromLabel('${json['level'] ?? 'INFO'}'),
      component: '${json['component'] ?? 'unknown'}',
      event: '${json['event'] ?? 'unknown'}',
      message: json['message'] is String ? json['message'] as String : null,
      sessionId: '${json['session'] ?? ''}',
      correlationId: json['correlation'] is num ? (json['correlation'] as num).toInt() : 0,
      profileId: json['profileId'] is String ? json['profileId'] as String : null,
      durationMs: json['durationMs'] is num ? (json['durationMs'] as num).toInt() : null,
      error: json['error'] is String ? json['error'] as String : null,
      stackTrace: json['stackTrace'] is String ? json['stackTrace'] as String : null,
      fields: json['fields'] is Map
          ? Map<String, String>.from(
              (json['fields'] as Map).map((k, v) => MapEntry('$k', '$v')))
          : const {},
    );
  }

  /// The one-line form used in the exported application.log.
  String toLine() {
    final buffer = StringBuffer()
      ..write(timestamp.toIso8601String())
      ..write(' [${level.label}] ')
      ..write('$component.$event');
    if (profileId != null) buffer.write(' profile=$profileId');
    if (durationMs != null) buffer.write(' ${durationMs}ms');
    if (message != null) buffer.write(' :: $message');
    if (error != null) buffer.write(' :: error=$error');
    for (final entry in fields.entries) {
      buffer.write(' ${entry.key}=${entry.value}');
    }
    if (stackTrace != null) buffer.write('\n$stackTrace');
    return buffer.toString();
  }
}
