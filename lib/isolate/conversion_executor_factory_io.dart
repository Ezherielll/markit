import 'conversion_executor.dart';
import 'isolate_executor.dart';

/// Desktop: worker isolate persist.
ConversionExecutor createPlatformExecutor() => IsolateExecutor();
