import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/ui/source/source_loader.dart';
import 'package:markit/ui/source/text_source_view.dart';
import 'package:markit/ui/theme/markit_theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, SourceText data) async {
    await tester.pumpWidget(MaterialApp(
      theme: PdflowTheme.light(),
      home: Scaffold(
        body: TextSourceView(data: data),
      ),
    ));
  }

  testWidgets('konten tampil apa adanya', (tester) async {
    await pump(tester, const SourceText(content: 'a,b\n1,2\n', truncated: false));
    expect(find.text('a,b\n1,2\n'), findsOneWidget);
    expect(find.text(Strings.sourceTruncated), findsNothing);
  });

  testWidgets('truncated: banner notifikasi tampil', (tester) async {
    await pump(tester, const SourceText(content: 'isi\n', truncated: true));
    expect(find.text(Strings.sourceTruncated), findsOneWidget);
    expect(find.text('isi\n'), findsOneWidget);
  });

  testWidgets('seleksi & scroll horizontal tersedia', (tester) async {
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
