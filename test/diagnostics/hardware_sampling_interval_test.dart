// Regression test for the effective sampling-interval clamp.
//
// The monitor's `interval` getter derives its sampling period from the stored
// `samplingIntervalSeconds`. A stored (or corrupted, e.g. loaded from an
// unvalidated document) value outside the supported range must be clamped so
// the monitor cannot spin on a zero interval or sample so rarely that pressure
// changes are missed. The settings `validate()` enforces 1–60 on the way in;
// this clamp is the defensive bound at the point of use.
import 'package:crispchess/diagnostics/hardware_protection.dart';
import 'package:crispchess/diagnostics/hardware_protection_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HardwareProtectionRuntime sampling interval clamp', () {
    test('clamps a corrupted zero interval up to one second', () {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(samplingIntervalSeconds: 0),
      );
      // Default decision level is normal, so interval == base.
      expect(runtime.interval, const Duration(seconds: 1));
    });

    test('clamps an excessive interval down to sixty seconds', () {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(samplingIntervalSeconds: 9999),
      );
      expect(runtime.interval, const Duration(seconds: 60));
    });

    test('keeps a valid in-range interval unchanged', () {
      final runtime = HardwareProtectionRuntime(
        settings: const HardwareProtectionSettings(samplingIntervalSeconds: 15),
      );
      expect(runtime.interval, const Duration(seconds: 15));
    });
  });
}
