// A retry replaces the engine process. The process it replaced may still exit
// afterwards (it was killed, or it was already dying), and that exit must not
// be recorded against the new process: dev3 could report "the engine exited
// with code -9" for a healthy second attempt.
@TestOn('vm && !windows')
library;

import 'dart:io';

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
}
