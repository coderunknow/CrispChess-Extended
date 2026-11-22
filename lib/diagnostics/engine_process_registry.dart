/// Tracks the engine processes this application started.
///
/// Memory monitoring that matches processes by name is fragile: two engines
/// can share a binary name, a renamed engine can stop matching, and a
/// short-lived helper can be mistaken for an engine. Instead, every engine
/// that spawns a process registers the process's stable id (its PID) here at
/// the same place it starts watching it, and unregisters it when the process
/// ends. The monitor then sums exactly the processes the application owns,
/// with no double counting and no name guessing.
///
/// The registry is process-global because the engines are created all over the
/// app (benchmarks, preflight, stability probes, the game screen). It holds
/// only an id and a label, so it costs nothing.
library;

/// One registered engine process.
class ManagedProcess {
  final int pid;
  final String label;
  final DateTime startedAt;

  const ManagedProcess({
    required this.pid,
    required this.label,
    required this.startedAt,
  });

  Map<String, dynamic> toJson() => {
        'pid': pid,
        'label': label,
        'startedAt': startedAt.toUtc().toIso8601String(),
      };
}

/// A set of engine processes the application is responsible for.
class ManagedProcessRegistry {
  final Map<int, ManagedProcess> _processes = {};

  /// Registers [pid] as a managed engine process. Re-registering the same pid
  /// refreshes its label rather than adding a second entry.
  void register(int pid, {required String label}) {
    if (pid <= 0) return;
    _processes[pid] = ManagedProcess(
      pid: pid,
      label: label,
      startedAt: _processes[pid]?.startedAt ?? DateTime.now(),
    );
  }

  /// Removes [pid]. Idempotent: removing an unknown pid is not an error.
  void unregister(int pid) {
    _processes.remove(pid);
  }

  bool contains(int pid) => _processes.containsKey(pid);

  int get count => _processes.length;

  /// The registered processes, in registration order.
  List<ManagedProcess> get entries => List.unmodifiable(_processes.values);

  List<int> get pids => List.unmodifiable(_processes.keys);

  /// Clears every entry. Used when a benchmark run ends so a fresh run does
  /// not inherit the previous run's process set.
  void clear() => _processes.clear();

  /// A snapshot of the currently registered PIDs, for per-run cleanup. A caller
  /// can capture this before a run and later remove only the PIDs registered
  /// during that run (see [removeNotIn]), preserving entries owned by other
  /// live engines that were already registered before the run started.
  Set<int> snapshotPids() => Set<int>.of(_processes.keys);

  /// Removes every registered PID that is not in [baseline], leaving the
  /// baseline entries (processes owned outside this run) untouched. Used to
  /// clean up a run's own processes without discarding other live engines'
  /// registrations.
  void removeNotIn(Set<int> baseline) {
    _processes.removeWhere((pid, _) => !baseline.contains(pid));
  }

  Map<String, dynamic> snapshotJson() => {
        'count': count,
        'processes': [for (final p in entries) p.toJson()],
      };
}

/// The process-global registry the engines write to.
ManagedProcessRegistry get managedProcessRegistry => _global;

final ManagedProcessRegistry _global = ManagedProcessRegistry();
