/// What an engine admits to supporting, without naming its class.
///
/// The benchmark has to be able to say "this engine does not advertise
/// `Threads`, so `Threads = 4` was not applied to it". Asking through an
/// interface rather than `engine is GenericUciEngine` keeps the benchmark code
/// free of a conditional import of the browser stub, and means an engine that
/// gains option support only has to implement this.
library;

/// An engine that speaks UCI options.
abstract interface class UciOptionAware {
  /// Names the engine advertised in its last handshake, in its own casing.
  List<String> get advertisedOptionNames;

  /// Whether [name] was advertised (case-insensitive, as engines match it).
  bool advertisesOption(String name);

  /// Sends `setoption name <name> value <value>`.
  ///
  /// Called only after [advertisesOption] said yes.
  void applyOption(String name, String value);

  /// Completes only after the engine acknowledges all preceding options.
  /// Failure makes the connection unusable; do not reuse a late readyok.
  Future<void> synchronizeOptions();
}

/// Optional search capability. Callers must reject an unsupported node budget,
/// not silently fall back to depth/time. Limits are alternatives, not combined.
abstract interface class NodeLimitedEngine {
  Future<String> bestMoveWithNodes(String positionCommand, int nodes);
}
