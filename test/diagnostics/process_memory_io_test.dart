// Regression tests for the native resource-reading seam, focused on the
// Linux /proc parsing that Hardware Protection depends on.
//
// These lock in the dev7 contract:
//  * the /proc/[pid]/stat CPU-time fields (utime, stime) are read at the
//    correct indices — reading them too early computes CPU time from the
//    fault counters (minflt/cminflt/majflt/cmajflt) instead of CPU ticks;
//  * unavailable figures stay null rather than a false zero.
import 'package:crispchess/diagnostics/process_memory_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a synthetic `/proc/[pid]/stat` line with distinct values for the
/// fields around the CPU-time fields so a wrong index is detectable.
///
/// The comm field (field 2) is wrapped in parentheses; the fields after the
/// last ')' are, 0-indexed: state(0) ppid(1) pgrp(2) session(3) tty_nr(4)
/// tpgid(5) flags(6) minflt(7) cminflt(8) majflt(9) cmajflt(10) utime(11)
/// stime(12) cutime(13) cstime(14) priority(15) nice(16) num_threads(17)
/// itrealvalue(18) starttime(19). All four fault counters sit before utime.
String _statLine({
  required int utime,
  required int stime,
  int minflt = 100,
  int cminflt = 1,
  int majflt = 2,
  int cmajflt = 3,
  int cutime = 99,
  int cstime = 101,
}) {
  return '1234 (my process name) S 100 1234 1234 0 -1 4194304 '
      '$minflt $cminflt $majflt $cmajflt $utime $stime $cutime $cstime '
      '0 0 20 0 1';
}

void main() {
  group('parseProcStatCpuTicks', () {
    test('reads utime and stime at the correct field indices', () {
      // Distinct values for the four fault counters (minflt, cminflt, majflt,
      // cmajflt) and for utime(11)/stime(12)/cutime(13)/cstime(14). The parser
      // must return utime and stime, not a fault counter or cutime.
      final ticks = parseProcStatCpuTicks(_statLine(utime: 100, stime: 200));
      expect(ticks, [100, 200]);
    });

    test('does not read a fault counter as a CPU tick', () {
      // The fault counters occupy indices 7-10; utime is index 11. A parser
      // that read utime at an earlier index would return a fault counter
      // (e.g. cmajflt=3) instead of utime=11.
      final ticks = parseProcStatCpuTicks(
          _statLine(utime: 11, stime: 22, cmajflt: 3, majflt: 2));
      expect(ticks, [11, 22]);
    });

    test('distinguishes utime from the adjacent stime/cutime fields', () {
      // utime=11, stime=22, cutime=33, cstime=44. A one-field shift would
      // return [22, 33] (stime, cutime); a two-field shift [33, 44]. The
      // correct read is [11, 22].
      final ticks = parseProcStatCpuTicks(
          _statLine(utime: 11, stime: 22, cutime: 33, cstime: 44));
      expect(ticks, [11, 22]);
    });

    test('returns null when there is no closing parenthesis', () {
      expect(parseProcStatCpuTicks('1234 no-comm-field S 1 2 3'), isNull);
    });

    test('returns null when the CPU fields are missing', () {
      // Truncated right after cmajflt (index 10): there are no utime(11)/
      // stime(12) tokens, so the read is unavailable rather than a false zero.
      expect(parseProcStatCpuTicks('1234 (p) S 1 2 3 4 5 6 7 8 9 10'), isNull);
    });

    test('returns null when a CPU field is non-numeric', () {
      // A valid layout (12 tokens before utime) but a non-numeric utime token
      // at index 11.
      final line =
          '1234 (p) S 1 2 3 4 5 6 7 8 9 10 abc 200 99 101 0 0 20 0 1';
      expect(parseProcStatCpuTicks(line), isNull);
    });
  });
}
