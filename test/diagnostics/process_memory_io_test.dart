// Regression tests for the native resource-reading seam, focused on the
// Linux /proc parsing that Hardware Protection depends on.
//
// These lock in the dev7 contract:
//  * the /proc/[pid]/stat CPU-time fields (utime, stime) are read at the
//    correct indices — an off-by-one here computed CPU time from stime +
//    cutime instead of utime + stime;
//  * unavailable figures stay null rather than a false zero.
import 'package:crispchess/diagnostics/process_memory_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a synthetic `/proc/[pid]/stat` line with distinct values for the
/// fields around the CPU-time fields so a wrong index is detectable.
///
/// The comm field (field 2) is wrapped in parentheses; the fields after the
/// last ')' are, 0-indexed: state(0) ppid(1) pgrp(2) session(3) tty_nr(4)
/// tpgid(5) flags(6) minflt(7) cmajflt(8) utime(9) stime(10) cutime(11)
/// cstime(12) priority(13) nice(14) num_threads(15) itrealvalue(16)
/// starttime(17).
String _statLine({
  required int utime,
  required int stime,
  int cmajflt = 7,
  int cutime = 99,
  int cstime = 101,
}) {
  return '1234 (my process name) S 100 1234 1234 0 -1 4194304 10 '
      '$cmajflt $utime $stime $cutime $cstime 0 0 20 0 1';
}

void main() {
  group('_parseProcStatCpuTicks', () {
    test('reads utime and stime at the correct field indices', () {
      // Distinct values for cmajflt(8), utime(9), stime(10), cutime(11),
      // cstime(12). The parser must return utime and stime, not stime/cutime
      // (the previous off-by-one) or cmajflt/utime.
      final ticks = _parseProcStatCpuTicks(_statLine(utime: 100, stime: 200));
      expect(ticks, [100, 200]);
    });

    test('distinguishes utime from the adjacent stime/cutime fields', () {
      // utime=11, stime=22, cutime=33, cstime=44. A one-field shift would
      // return [22, 33] (stime, cutime); a two-field shift [33, 44]. The
      // correct read is [11, 22].
      final ticks = _parseProcStatCpuTicks(
          _statLine(utime: 11, stime: 22, cutime: 33, cstime: 44));
      expect(ticks, [11, 22]);
    });

    test('returns null when there is no closing parenthesis', () {
      expect(_parseProcStatCpuTicks('1234 no-comm-field S 1 2 3'), isNull);
    });

    test('returns null when the CPU fields are missing', () {
      // Truncated right after cmajflt (index 8): there are no utime(9)/stime(10)
      // tokens, so the read is unavailable rather than a false zero.
      expect(_parseProcStatCpuTicks('1234 (p) S 1 2 3 4 5 6 7 8'), isNull);
    });

    test('returns null when a CPU field is non-numeric', () {
      // A valid layout but a non-numeric utime token.
      final line =
          '1234 (p) S 1 2 3 4 5 6 7 8 abc 200 99 101 0 0 20 0 1';
      expect(_parseProcStatCpuTicks(line), isNull);
    });
  });
}
