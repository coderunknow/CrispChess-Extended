// Regression test for CSV escaping in the resource telemetry report.
//
// A telemetry value that contains a comma, a double quote or a line break
// must be quoted (with embedded quotes doubled) so it cannot split a row
// across columns and shift every following field. Before the fix, raw values
// were written unquoted, so a state string with a comma corrupted the CSV.
import 'package:crispchess/diagnostics/hardware_protection.dart';
import 'package:crispchess/diagnostics/resource_telemetry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ResourceTelemetryLog CSV escaping', () {
    test('a value containing a comma is quoted', () {
      final log = ResourceTelemetryLog();
      log.add(_record(benchmarkMode: 'quick, deep'));
      final csv = log.toCsv();
      final dataLine = csv.split('\n').last;
      // The comma inside the value is protected by quotes, so the row still has
      // exactly 19 columns.
      expect(_columnCount(dataLine), 19);
      expect(dataLine, contains('"quick, deep"'));
    });

    test('a value containing a double quote has the quote doubled', () {
      final log = ResourceTelemetryLog();
      log.add(_record(benchmarkMode: 'a "quoted" mode'));
      final csv = log.toCsv();
      final dataLine = csv.split('\n').last;
      expect(_columnCount(dataLine), 19);
      expect(dataLine, contains('"a ""quoted"" mode"'));
    });

    test('an empty log writes only the header row', () {
      final csv = ResourceTelemetryLog().toCsv();
      expect(csv.split('\n').length, 1);
    });

    test('a plain value is written unquoted', () {
      final log = ResourceTelemetryLog();
      log.add(_record(benchmarkMode: 'standard'));
      final dataLine = log.toCsv().split('\n').last;
      expect(dataLine, contains(',standard,'));
    });
  });
}

/// Count CSV columns on a single data line, honouring quoted fields (which may
/// contain commas). A naive split would miscount a line whose value was quoted
/// incorrectly, so this mirrors the escaping contract the writer must uphold.
int _columnCount(String line) {
  int columns = 0;
  bool inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      // A pair of consecutive quotes is an escaped quote inside a field.
      if (i + 1 < line.length && line[i + 1] == '"') {
        i++;
      } else {
        inQuotes = !inQuotes;
      }
    } else if (char == ',' && !inQuotes) {
      columns++;
    }
  }
  return columns + 1;
}

ResourceTelemetryRecord _record({required String benchmarkMode}) {
  return ResourceTelemetryRecord(
    timestamp: DateTime.utc(2026, 11, 20, 12, 0, 0),
    engineProcessCount: 2,
    engineLifecycleState: 'running',
    selectedEngineCount: 2,
    benchmarkMode: benchmarkMode,
    elapsedSeconds: 1.5,
    threads: 4,
    hashMb: 128,
    pressureLevel: ResourcePressureLevel.normal,
  );
}
