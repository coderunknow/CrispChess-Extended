import 'dart:isolate';

import 'cluster_bootstrap.dart';

const int bootstrapBatchSize = 200;

Future<BootstrapBatchResult> runBootstrapBatch(BootstrapBatchRequest request) =>
    Isolate.run(() => computeBootstrapBatch(request));
