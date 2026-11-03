import 'cluster_bootstrap.dart';

const int bootstrapBatchSize = 25;

Future<BootstrapBatchResult> runBootstrapBatch(BootstrapBatchRequest request) async {
  // Browsers have no dart:isolate. Small batches yield between refits so the
  // page can still paint and process pause/cancel input.
  await Future<void>.delayed(Duration.zero);
  return computeBootstrapBatch(request);
}
