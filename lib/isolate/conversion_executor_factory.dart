import 'conversion_executor.dart';
import 'conversion_executor_factory_stub.dart'
    if (dart.library.io) 'conversion_executor_factory_io.dart'
    if (dart.library.js_interop) 'conversion_executor_factory_web.dart';

/// Platform-specific executor factory.
/// - IO (desktop): [IsolateExecutor] — persistent worker isolate.
/// - Web: [InlineExecutor] — inline pipeline on main isolate.
ConversionExecutor createConversionExecutor() => createPlatformExecutor();
