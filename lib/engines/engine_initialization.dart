import 'chess_engine.dart';

/// A startup failure that retains the original cause instead of reducing it to
/// "Bad state". UIs can display/copy [toString]; callers can inspect the fields.
class EngineInitializationException implements Exception {
  final String engine;
  final String version;
  final String stage;
  final String platform;
  final Object cause;
  final StackTrace? causeStack;
  final String? libraryPath;
  final String? symbol;
  final int? nativeCode;
  final int? elapsedMicros;

  const EngineInitializationException({
    required this.engine,
    required this.version,
    required this.stage,
    required this.platform,
    required this.cause,
    this.causeStack,
    this.libraryPath,
    this.symbol,
    this.nativeCode,
    this.elapsedMicros,
  });

  Map<String, Object?> toJson() => {
    'engine': engine, 'version': version, 'stage': stage,
    'platform': platform, 'causeType': cause.runtimeType.toString(),
    'cause': cause.toString(),
    if (libraryPath != null) 'libraryPath': libraryPath,
    if (symbol != null) 'symbol': symbol,
    if (nativeCode != null) 'nativeCode': nativeCode,
    if (elapsedMicros != null) 'elapsedMicros': elapsedMicros,
    if (causeStack != null) 'causeStack': causeStack.toString(),
  };

  @override
  String toString() {
    final details = [
      'engine=$engine $version', 'platform=$platform', 'stage=$stage',
      if (libraryPath != null) 'library=$libraryPath',
      if (symbol != null) 'symbol=$symbol',
      if (nativeCode != null) 'nativeCode=$nativeCode',
      if (elapsedMicros != null) 'elapsedMicros=$elapsedMicros',
    ];
    var message = '${details.join('; ')}\n$cause';
    if (stage == 'load-library' && nativeCode == 126) {
      message += '\nThe library or one of its dependencies is missing. '
          'Use a complete release archive; do not substitute another engine.';
    }
    return message;
  }
}

/// Normal return is only successful when the engine is actually ready.
void requireEngineReady(ChessEngine engine, {required String platform}) {
  if (engine.state != EngineState.ready) {
    throw EngineInitializationException(
      engine: engine.name, version: engine.version,
      stage: 'verify-ready', platform: platform,
      cause: StateError('initialize returned with state ${engine.state.name}'),
    );
  }
}

int? windowsLoaderCode(Object error) {
  final match = RegExp(r'error code:\s*(\d+)').firstMatch(error.toString());
  return match == null ? null : int.tryParse(match.group(1)!);
}
