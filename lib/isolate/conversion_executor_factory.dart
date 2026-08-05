import 'conversion_executor.dart';
import 'conversion_executor_factory_stub.dart'
    if (dart.library.io) 'conversion_executor_factory_io.dart'
    if (dart.library.js_interop) 'conversion_executor_factory_web.dart';

/// Factory executor sesuai platform.
/// - IO (desktop): [IsolateExecutor] — worker isolate persist.
/// - Web: [InlineExecutor] — pipeline di main isolate.
ConversionExecutor createConversionExecutor() => createPlatformExecutor();
