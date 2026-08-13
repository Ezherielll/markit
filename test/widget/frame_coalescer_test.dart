import 'package:flutter_test/flutter_test.dart';
import 'package:markit/ui/frame_coalescer.dart';

void main() {
  testWidgets('beberapa schedule dalam satu frame → satu onFrame', (tester) async {
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

  testWidgets('dispose membatalkan callback yang belum jalan', (tester) async {
    var count = 0;
    final coalescer = FrameCoalescer(onFrame: () => count++);

    coalescer.schedule();
    coalescer.dispose();
    await tester.pump();

    expect(count, 0);
  });
}
