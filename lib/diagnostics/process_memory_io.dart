/// Native resource reading for desktop and mobile hosts.
///
/// This is the `dart:io` implementation of the Hardware Protection resource
/// seam. It reads only what the operating system exposes without shelling out
/// on a hot path:
///
///  * Linux reads `/proc/meminfo` for system memory, `/proc/<pid>/statm` for a
///    process's resident memory, and walks `/proc` for child processes.
///  * macOS reads `sysctl hw.memsize` for total memory and `ps` for a
///    process's resident set; child enumeration is not performed.
///  * Windows reads system memory via the Win32 `GlobalMemoryStatusEx` API
///    (FFI). It has no in-process reader for another process's memory without
///    FFI, so engine-process figures are reported as unavailable rather than
///    guessed.
///
/// Every read is best-effort and wrapped: a platform that cannot provide a
/// figure returns `null` for it, which the model keeps distinct from zero.
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'hardware_protection.dart'
    show HardwarePlatform, ProcessMemorySample, SystemMemorySample;

/// Which platform family this host belongs to.
HardwarePlatform hardwarePlatform() {
  if (Platform.isWindows) return HardwarePlatform.windows;
  if (Platform.isMacOS) return HardwarePlatform.macos;
  if (Platform.isAndroid) return HardwarePlatform.android;
  if (Platform.isIOS) return HardwarePlatform.ios;
  if (Platform.isLinux) return HardwarePlatform.linux;
  return HardwarePlatform.unknown;
}

/// The application process's cumulative CPU time, for the sampling window's
/// CPU percentage. Summed across threads, so it can exceed the wall-clock
/// window on a multi-threaded process; the metric is labelled accordingly.
///
/// `dart:io`'s [ProcessInfo] exposes no CPU-time figure, so on Linux this
/// reads `/proc/self/stat` (the process's own user + system time). On every
/// other platform there is no reader, so it returns null rather than a
/// constant zero — a zero would be treated as a measured counter and report
/// a false 0% CPU while the application is actually busy.
Duration? readApplicationCpu() {
  try {
    if (Platform.isLinux) return _linuxApplicationCpu();
  } catch (_) {
    // Fall through to unavailable.
  }
  return null;
}

/// Cumulative CPU time of this process from `/proc/self/stat`: the sum of the
/// user and system time fields, converted from clock ticks to a duration.
///
/// Returns `null` (not `Duration.zero`) when the fields cannot be parsed: a
/// zero is a measured value, and returning it on a parse failure would report a
/// false 0% CPU while the application is actually busy.
Duration? _linuxApplicationCpu() {
  final ticks =
      _parseProcStatCpuTicks(File('/proc/self/stat').readAsStringSync());
  if (ticks == null) return null;
  final ticksPerSecond = _linuxClockTicksPerSecond();
  final millis = ((ticks[0] + ticks[1]) * 1000 / ticksPerSecond).toInt();
  return Duration(milliseconds: millis);
}

/// Parse the cumulative CPU time (utime + stime, in clock ticks) from a
/// `/proc/[pid]/stat` text. Returns `[utime, stime]`, or `null` when the
/// fields cannot be parsed.
///
/// Split out from [_linuxApplicationCpu] so the field indexing can be tested
/// with a fixture without touching the real `/proc`. After the `comm` field
/// (the last `)`) the 0-based tokens are state(0) ppid(1) ... cmajflt(8)
/// utime(9) stime(10): utime is field 12 and stime field 13 of /proc, and
/// after dropping pid(1) and comm(2) the 0-based index is fieldNumber - 3.
/// Reading utime at index 10 and stime at 11 (the previous values) shifted
/// every field by one, computing the CPU time from stime + cutime instead of
/// utime + stime.
@visibleForTesting
List<int>? _parseProcStatCpuTicks(String text) {
  final close = text.lastIndexOf(')');
  if (close < 0) return null;
  // Trim before splitting: the substring right after ')' begins with a space,
  // and a split that keeps a leading empty token shifts every index by one,
  // reading the wrong fields.
  final rest = text.substring(close + 1).trim().split(RegExp(r'\s+'));
  final utime = int.tryParse(rest.length > 9 ? rest[9] : '');
  final stime = int.tryParse(rest.length > 10 ? rest[10] : '');
  if (utime == null || stime == null) return null;
  return [utime, stime];
}

int? _pageSizeCache;
int? _clkTckCache;

/// The OS memory page size in bytes (`getconf PAGE_SIZE`), cached after the
/// first read. `dart:io`'s [Platform] exposes no page size, so this is read
/// once from `getconf`; 4096 is the standard fallback when it is unavailable.
int _linuxPageSize() {
  final cached = _pageSizeCache;
  if (cached != null) return cached;
  int size;
  try {
    final result = Process.runSync('getconf', ['PAGE_SIZE']);
    size = int.tryParse(String.fromCharCodes(result.stdout).trim()) ?? 4096;
  } catch (_) {
    size = 4096;
  }
  // A pathological 0 from a misconfigured host would turn every page count
  // into a zero resident size; fall back to the standard 4096.
  if (size <= 0) size = 4096;
  _pageSizeCache = size;
  return size;
}

/// Clock ticks per second (`getconf CLK_TCK`), cached after the first read.
/// 100 is the near-universal Linux default when `getconf` is unavailable.
int _linuxClockTicksPerSecond() {
  final cached = _clkTckCache;
  if (cached != null) return cached;
  int ticks;
  try {
    final result = Process.runSync('getconf', ['CLK_TCK']);
    ticks = int.tryParse(String.fromCharCodes(result.stdout).trim()) ?? 100;
  } catch (_) {
    ticks = 100;
  }
  // A pathological 0 would make the tick→millisecond conversion divide by
  // zero (yielding Infinity, which `.toInt()` rejects with a RangeError and
  // would crash the CPU sampler). Fall back to the near-universal 100.
  if (ticks <= 0) ticks = 100;
  _clkTckCache = ticks;
  return ticks;
}

/// The application process's resident memory, or null where the platform
/// cannot report it.
int? applicationRss() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    try {
      return ProcessInfo.maxRss;
    } catch (_) {
      return null;
    }
  }
}

/// System-wide memory. On Linux both total and available come from
/// `/proc/meminfo`; on macOS the total comes from `sysctl` and availability is
/// not reported (the model falls back to the total); elsewhere nothing is
/// reported.
SystemMemorySample readSystemMemory() {
  try {
    if (Platform.isLinux) return _linuxSystemMemory();
    if (Platform.isWindows) return _windowsSystemMemory();
    if (Platform.isMacOS) return _macosSystemMemory();
  } catch (_) {
    // Fall through to the "unavailable" sample.
  }
  return const SystemMemorySample();
}

SystemMemorySample _linuxSystemMemory() {
  final text = File('/proc/meminfo').readAsStringSync();
  int? kib(String key) {
    for (final line in text.split('\n')) {
      if (line.startsWith(key)) {
        final parts = line.split(RegExp(r'\s+'));
        return int.tryParse(parts.length > 2 ? parts[1] : '');
      }
    }
    return null;
  }

  final totalKib = kib('MemTotal:');
  final availableKib = kib('MemAvailable:');
  return SystemMemorySample(
    totalBytes: totalKib == null ? null : totalKib * 1024,
    availableBytes: availableKib == null ? null : availableKib * 1024,
  );
}

SystemMemorySample _macosSystemMemory() {
  final result = Process.runSync('sysctl', ['-n', 'hw.memsize']);
  if (result.exitCode != 0) return const SystemMemorySample();
  final totalBytes = int.tryParse(String.fromCharCodes(result.stdout).trim());
  return SystemMemorySample(totalBytes: totalBytes);
}

/// Win32 `MEMORYSTATUSEX` layout. The two `DWORD` fields are 4 bytes each and
/// the seven `SIZE_T` fields are 8 bytes each on 64-bit Windows. Dart's FFI
/// aligns the `UInt64` fields to 8 bytes, matching the native layout, so
/// `ullTotalPhys`/`ullAvailPhys` are read from the correct offsets.
sealed class _MemoryStatusEx extends Struct {
  @Uint32()
  external int dwLength;
  @Uint32()
  external int dwMemoryLoad;
  @Uint64()
  external int ullTotalPhys;
  @Uint64()
  external int ullAvailPhys;
  @Uint64()
  external int ullTotalPageFile;
  @Uint64()
  external int ullAvailPageFile;
  @Uint64()
  external int ullTotalVirtual;
  @Uint64()
  external int ullAvailVirtual;
  @Uint64()
  external int ullAvailExtendedVirtual;
}

typedef _GlobalMemoryStatusEx = Int32 Function(Pointer<_MemoryStatusEx>);
typedef _GlobalMemoryStatusExImp = int Function(Pointer<_MemoryStatusEx>);

DynamicLibrary? _windowsKernel32Cache;
_GlobalMemoryStatusExImp? _globalMemoryStatusEx;

/// The Win32 `GlobalMemoryStatusEx` entry point from kernel32, resolved once
/// and cached. Returns null where the library or symbol cannot be loaded, so
/// the reader degrades to an empty sample instead of throwing on the hot path.
_GlobalMemoryStatusExImp? _windowsGlobalMemoryStatusEx() {
  if (_globalMemoryStatusEx != null) return _globalMemoryStatusEx;
  try {
    final lib = _windowsKernel32Cache ??= DynamicLibrary.open('kernel32.dll');
    // lookupFunction<AbiType, DartType> returns the Dart-facing type, so the
    // ABI signature (Int32/Pointer) is first and the Dart signature (int) is
    // second.
    _globalMemoryStatusEx =
        lib.lookupFunction<_GlobalMemoryStatusEx, _GlobalMemoryStatusExImp>(
            'GlobalMemoryStatusEx');
    return _globalMemoryStatusEx;
  } catch (_) {
    return null;
  }
}

/// System memory on Windows via the Win32 `GlobalMemoryStatusEx` API. Provides
/// a real total and available figure so the automatic memory budget resolves
/// on Windows instead of always falling through to an empty sample (which left
/// the default-configured budget unusable and Hardware Protection inert).
/// Best-effort and wrapped: any failure returns the empty sample.
SystemMemorySample _windowsSystemMemory() {
  final fn = _windowsGlobalMemoryStatusEx();
  if (fn == null) return const SystemMemorySample();
  final buffer = calloc<_MemoryStatusEx>();
  try {
    // `dwLength` must be set to the size of the struct before the call.
    buffer.ref.dwLength = sizeOf<_MemoryStatusEx>();
    if (fn(buffer) == 0) return const SystemMemorySample();
    return SystemMemorySample(
      totalBytes: buffer.ref.ullTotalPhys,
      availableBytes: buffer.ref.ullAvailPhys,
    );
  } finally {
    calloc.free(buffer);
  }
}

/// Resident memory of one process, or an empty sample when the platform cannot
/// report it.
ProcessMemorySample readProcessMemory(int pid) {
  try {
    if (Platform.isLinux) return _linuxProcessMemory(pid);
    if (Platform.isMacOS) return _macosProcessMemory(pid);
  } catch (_) {
    // Fall through.
  }
  return ProcessMemorySample(pid: pid);
}

ProcessMemorySample _linuxProcessMemory(int pid) {
  // /proc/<pid>/statm: size resident shared text lib data dt, in pages.
  final text = File('/proc/$pid/statm').readAsStringSync();
  final fields = text.split(RegExp(r'\s+')).where((f) => f.isNotEmpty).toList();
  if (fields.length < 2) return ProcessMemorySample(pid: pid);
  final residentPages = int.tryParse(fields[1]);
  if (residentPages == null) return ProcessMemorySample(pid: pid);
  return ProcessMemorySample(
    pid: pid,
    rssBytes: residentPages * _linuxPageSize(),
  );
}

ProcessMemorySample _macosProcessMemory(int pid) {
  final result = Process.runSync('ps', ['-o', 'rss=', '-p', '$pid']);
  if (result.exitCode != 0) return ProcessMemorySample(pid: pid);
  final kb = int.tryParse(String.fromCharCodes(result.stdout).trim());
  if (kb == null) return ProcessMemorySample(pid: pid);
  return ProcessMemorySample(pid: pid, rssBytes: kb * 1024);
}

/// Every parent→children mapping the host can enumerate, in a single pass over
/// `/proc`. Only Linux can enumerate children cheaply; every other platform
/// returns an empty map and the monitor relies on the managed-process registry
/// instead. Doing one pass here (rather than one per managed process) keeps the
/// per-sample cost of process-tree accounting bounded no matter how many
/// engines are resident.
Map<int, List<int>> allChildrenByParent() {
  if (!Platform.isLinux) return const {};
  try {
    final map = <int, List<int>>{};
    for (final entry in Directory('/proc').listSync()) {
      // Derive the directory name from `entry.path`, not the last URI segment:
      // a directory's URI carries a trailing slash, so `pathSegments.last` is
      // the empty string and the numeric filter below would reject every
      // `/proc/<pid>` directory — silently enumerating no processes at all.
      // `entry.path` has no trailing slash, so its last non-empty `/`-separated
      // segment is the directory name (the PID).
      final name = entry.path.split('/').where((s) => s.isNotEmpty).last;
      if (!RegExp(r'^\d+$').hasMatch(name)) continue;
      // `${entry.path}` (not `'$entry.path'`): the latter interpolates
      // `entry` and leaves `.path` as literal text, handing _readProcStat a
      // malformed path so every process is dropped by the catch below.
      final stat = _readProcStat('${entry.path}');
      if (stat == null) continue;
      final child = int.tryParse(name);
      if (child == null) continue;
      (map[stat.ppid] ??= <int>[]).add(child);
    }
    return map;
  } catch (_) {
    return const {};
  }
}

/// Child process ids of [pid], best-effort. Derived from the single-pass
/// [allChildrenByParent] enumeration.
List<int> childPidsOf(int pid) => allChildrenByParent()[pid] ?? const [];

/// Reads the parent pid from `/proc/<path>/stat`. The process name can contain
/// spaces and parentheses, so the fields after the final ')' are parsed.
({int ppid, int pid})? _readProcStat(String path) {
  try {
    final text = File('$path/stat').readAsStringSync();
    final space = text.indexOf(' ');
    final close = text.lastIndexOf(')');
    if (space < 0 || close < 0) return null;
  final pid = int.tryParse(text.substring(0, space));
  // Trim before splitting so a leading space cannot leave a stray empty token
  // at index 0 and shift the ppid (index 1) onto the state token.
  final rest = text.substring(close + 1).trim().split(RegExp(r'\s+'));
  // After ')' the fields are: state(0) ppid(1) ...
  final ppid = int.tryParse(rest.length > 1 ? rest[1] : '');
  if (pid == null || ppid == null) return null;
    return (ppid: ppid, pid: pid);
  } catch (_) {
    return null;
  }
}

/// Battery/power state where the host exposes it. Linux exposes a
/// `/sys/class/power_supply/<battery>/status` file; other platforms return
/// null and the capability matrix reports the difference.
String? readPowerState() {
  if (!Platform.isLinux) return null;
  try {
    final base = Directory('/sys/class/power_supply');
    if (!base.existsSync()) return null;
    for (final entry in base.listSync()) {
      if (entry is! Directory) continue;
      final status = File('${entry.path}/status');
      if (!status.existsSync()) continue;
      final text = status.readAsStringSync();
      if (text.contains('Discharging')) return 'onBattery';
      if (text.contains('Charging') || text.contains('Full')) return 'onCharger';
    }
  } catch (_) {
    // No readable power supply: report unavailable rather than invent one.
  }
  return null;
}

/// Thermal/performance-pressure state where the host exposes a thermal zone.
/// Linux exposes `/sys/class/thermal/thermal_zone*/temp`; the value is only
/// reported when it is present and parseable. This is a *signal*, never a
/// direct temperature control.
String? readThermalState() {
  if (!Platform.isLinux) return null;
  try {
    final base = Directory('/sys/class/thermal');
    if (!base.existsSync()) return null;
    int? hottestMilli;
    for (final entry in base.listSync()) {
      if (entry is! Directory) continue;
      final tempFile = File('${entry.path}/temp');
      if (!tempFile.existsSync()) continue;
      final milli = int.tryParse(tempFile.readAsStringSync().trim());
      if (milli == null) continue;
      hottestMilli = (hottestMilli == null || milli > hottestMilli)
          ? milli
          : hottestMilli;
    }
    if (hottestMilli == null) return null;
    // Millidegrees Celsius. Below 70 is nominal, below 85 moderate, above
    // that a serious performance-pressure signal.
    final celsius = hottestMilli / 1000;
    if (celsius >= 85) return 'serious';
    if (celsius >= 70) return 'moderate';
    return 'nominal';
  } catch (_) {
    return null;
  }
}
