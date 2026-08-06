import 'package:flutter_test/flutter_test.dart';
import 'package:markit/app.dart';

void main() {
  testWidgets('app boots to home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PdflowApp());
    expect(find.text('MarkIt'), findsOneWidget);
    expect(find.text('Choose PDF files'), findsOneWidget);
  });
}
