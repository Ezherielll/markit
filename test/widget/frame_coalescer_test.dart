import 'package:flutter_test/flutter_test.dart';
import 'package:markit/ui/frame_coalescer.dart';

void main() {
  testWidgets('multiple schedules in single frame -> one onFrame', (tester) async {
    var count = 0;
    final coalescer = FrameCoalescer(onFrame: () => count++);

    coalescer.schedule();
    coalescer.schedule();
    coalescer.schedule();
    await tester.pump();

    expect(count, 1);

    coalescer.schedule();
    await tester.pump();
    expect(count, 2);
  });

  testWidgets('dispose cancels pending callback', (tester) async {
    var count = 0;
    final coalescer = FrameCoalescer(onFrame: () => count++);

    coalescer.schedule();
    coalescer.dispose();
    await tester.pump();

    expect(count, 0);
  });
}
