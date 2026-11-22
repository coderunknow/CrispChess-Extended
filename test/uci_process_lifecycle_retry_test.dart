// A retry replaces the engine process. The process it replaced may still exit
// afterwards (it was killed, or it was already dying), and that exit must not
// be recorded against the new process: dev3 could report "the engine exited
// with code -9" for a healthy second attempt.
@TestOn('vm && !windows')
library;

import 'dart:io';

import 'package:crispchess/diagnostics/engine_process_registry.dart';
import 'package:crispchess/engines/uci_process_lifecycle.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host with UciProcessLifecycle {
  int lost = 0;

  @override
  void onProcessLost() => lost++;

  @override
  String get processLabel => 'Host';
}

void main() {
  test('the exit of a replaced process is not reported for its successor',
      () async {
    final host = _Host();
    final first = await Process.start('sleep', ['30']);
    host.watchProcess(first);
    final second = await Process.start('sleep', ['30']);
    host.watchProcess(second);

    first.kill(ProcessSignal.sigkill);
    await first.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(host.processGone, isFalse,
        reason: 'the watched (second) process is still running');
    expect(host.lost, 0);

    second.kill(ProcessSignal.sigkill);
    await second.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.processGone, isTrue);
    expect(host.lost, 1);
    final report = await host.processDeathReport();
    expect(report.exitCode, isNot(0));
    host.stopWatchingProcess();
  });

  test('a death just after teardown still records its exit code', () async {
    final host = _Host();
    final process = await Process.start(
        'bash', ['-c', 'echo "fatal: out of memory" >&2; sleep 0.2; exit 7']);
    host.watchProcess(process);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    host.stopWatchingProcess();
    await process.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final report = await host.processDeathReport();
    expect(report.exitCode, 7);
  });

  test('stdout loss does not unregister a still-running process', () async {
    // Regression: `releaseOnLoss()` is routed from stdout closing, but it
    // unregistered the PID as if the process had died. A GenericUciEngine can
    // close stdout while the process still runs, which dropped a live,
    // still-consuming process from the memory monitor's accounting. stdout loss
    // must only release pending work; the PID is unregistered only when the
    // process actually exits (or on explicit teardown).
    final host = _Host();
    final process = await Process.start('sleep', ['30']);
    final pid = process.pid;
    host.watchProcess(process);
    expect(managedProcessRegistry.contains(pid), isTrue);

    // Simulate stdout closing while the process is still alive.
    host.releaseOnLoss();

    // onProcessLost is called (waiters released) but the PID stays registered
    // because the process is still running and still consuming memory.
    expect(host.lost, 1);
    expect(managedProcessRegistry.contains(pid), isTrue,
        reason: 'a live process must stay registered for memory accounting');

    // releaseOnLoss is idempotent: a second stdout-loss signal does not
    // double-report.
    host.releaseOnLoss();
    expect(host.lost, 1);

    // Now the process truly exits: the exit handler unregisters it.
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(managedProcessRegistry.contains(pid), isFalse,
        reason: 'the exit path must unregister the process');
    host.stopWatchingProcess();
  });

  test('teardown keeps the PID registered until the process actually exits',
      () async {
    // Regression: stopWatchingProcess() unregistered the PID before
    // stdin.close()/kill() completed, so a Hardware Protection sample taken
    // during teardown (process still alive, still holding memory) omitted the
    // live engine. Teardown must detach the stderr watcher only and keep the
    // registration; the exit-code callback is what finally unregisters it.
    final host = _Host();
    final process = await Process.start('sleep', ['30']);
    final pid = process.pid;
    host.watchProcess(process);
    expect(managedProcessRegistry.contains(pid), isTrue);

    // Teardown: detach the watcher while the process is still alive.
    host.beginProcessDispose();
    host.stopWatchingProcess();
    // Still alive and still consuming memory: must stay registered.
    expect(managedProcessRegistry.contains(pid), isTrue,
        reason: 'a not-yet-dead engine must remain in memory accounting');

    // Only when the process exits does the registration go away.
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(managedProcessRegistry.contains(pid), isFalse,
        reason: 'the exit callback must unregister after teardown');
  });
}
