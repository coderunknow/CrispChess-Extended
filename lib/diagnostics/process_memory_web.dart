/// Web implementation of the Hardware Protection resource seam.
///
/// A browser cannot inspect the host's process tree, other processes' memory,
/// or system memory availability from Dart. Every figure is therefore
/// unavailable, and the capability matrix reports that honestly. The app still
/// runs: the Hardware Protection model treats an unavailable reading as "no
/// data" rather than as a zero, so nothing is mis-measured.
library;

import 'hardware_protection.dart'
    show HardwarePlatform, ProcessMemorySample, SystemMemorySample;

/// Always the web platform in a browser build.
HardwarePlatform hardwarePlatform() => HardwarePlatform.web;

/// No per-process CPU counter is exposed to a web build.
Duration? readApplicationCpu() => null;

/// No per-process memory is exposed to a web build.
int? applicationRss() => null;

/// No system memory figures are exposed to a web build.
SystemMemorySample readSystemMemory() => const SystemMemorySample();

/// No other process's memory is visible to a web build.
ProcessMemorySample readProcessMemory(int pid) => ProcessMemorySample(pid: pid);

/// A browser cannot enumerate host processes.
List<int> childPidsOf(int pid) => const [];

/// A browser cannot enumerate host processes.
Map<int, List<int>> allChildrenByParent() => const {};

/// No power state is exposed to a web build.
String? readPowerState() => null;

/// No thermal state is exposed to a web build.
String? readThermalState() => null;
