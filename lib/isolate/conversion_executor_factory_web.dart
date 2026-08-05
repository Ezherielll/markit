import 'conversion_executor.dart';
import 'inline_executor.dart';

/// Web: pipeline inline di main isolate.
ConversionExecutor createPlatformExecutor() => InlineExecutor();
