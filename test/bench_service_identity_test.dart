@TestOn('vm')
library;

import 'dart:io';
import 'package:crispchess/bench/benchmark_service.dart';
import 'package:crispchess/bench/benchmark_run.dart';
import 'package:crispchess/bench/benchmark_storage_base.dart';
import 'package:crispchess/bench/benchmark_store.dart';
import 'package:crispchess/engines/generic_uci_engine_stub.dart';
import 'package:crispchess/services/engine_profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/bench_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('automatic detection distinguishes saved overrides from run settings', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('identity_service');
    addTearDown(() => dir.deleteSync(recursive: true));
    final binary = File('${dir.path}/engine')..writeAsStringSync('unchanged binary');
    final profiles = EngineProfileStore();
    final profile = EngineProfile(id: 'p', name: 'test', path: binary.path,
        optionOverrides: {'Hash': '16'});
    await profiles.add(profile);
    final store = BenchmarkStore(storage: MemoryBenchmarkStorage());
    final service = BenchmarkService(store: store, profileStore: profiles);
    final initial = await service.identityFor('custom:p');
    expect(initial.configuration, {'Hash': '16'});
    final run = (await runScriptedBenchmark()).run;
    // Remember a measured identity, with different benchmark-only options.
    final document = run.toJson();
    document['engines'] = [initial.withConfiguration({'Hash': '64'}).toJson()];
    await store.saveRun(BenchmarkRun.fromJson(document));
    final unchanged = await service.decideAfterChange('custom:p');
    expect(unchanged.shouldRun, isFalse);
    expect(unchanged.reason, contains('unchanged'));
    await profiles.save([profile.copyWith(optionOverrides: {'Hash': '32'})]);
    final changed = await service.decideAfterChange('custom:p');
    expect(changed.shouldRun, isTrue);
    expect(changed.reason, contains('configuration changed'));
    await profiles.save([profile.copyWith(optionOverrides: {})]);
    expect((await service.identityFor('custom:p')).configuration, isEmpty);
    expect((await service.decideAfterChange('custom:p')).shouldRun, isTrue);
  });
}
