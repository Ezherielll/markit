import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/ui/source/source_loader.dart';
import 'package:markit/ui/source/text_source_view.dart';
import 'package:markit/ui/theme/markit_theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, SourceText data) async {
    await tester.pumpWidget(MaterialApp(
      theme: MarkitTheme.light(),
      home: Scaffold(
        body: TextSourceView(data: data),
      ),
    ));
  }

  testWidgets('content displays as is', (tester) async {
    await pump(tester, const SourceText(content: 'a,b\n1,2\n', truncated: false));
    expect(find.text('a,b\n1,2\n'), findsOneWidget);
    expect(find.text(Strings.sourceTruncated), findsNothing);
  });

  testWidgets('truncated: notification banner displays', (tester) async {
    await pump(tester, const SourceText(content: 'isi\n', truncated: true));
    expect(find.text(Strings.sourceTruncated), findsOneWidget);
    expect(find.text('isi\n'), findsOneWidget);
  });

  testWidgets('selection & horizontal scroll available', (tester) async {
    await pump(
      tester,
      SourceText(content: 'baris panjang ' * 200, truncated: false),
    );
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(
      tester
          .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .scrollDirection,
      Axis.horizontal,
    );
  });
}
