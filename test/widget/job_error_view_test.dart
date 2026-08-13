import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/widgets/job_error_view.dart';

void main() {
  QueuedFile job({String? errorType, String? errorMessage}) => QueuedFile(
        id: '1',
        input: PdfInput(name: 'a.pdf', path: 'C:/a.pdf'),
      )
        ..status = JobStatus.failed
        ..errorType = errorType
        ..errorMessage = errorMessage;

  testWidgets('menampilkan judul terpetakan + pesan lengkap (wrap, bukan ellipsis)',
      (tester) async {
    final longMessage = 'Gagal membaca file: format tidak dikenali. '
        'Coba periksa apakah file masih valid, atau konversi ulang '
        'dari aplikasi sumbernya. Pesan detail ini sengaja panjang '
        'agar menguji bahwa teks tidak terpotong.';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: JobErrorView(job: job(
          errorType: 'corrupt',
          errorMessage: longMessage,
        )),
      ),
    ));

    // Judul terpetakan dari errorType.
    expect(find.text(Strings.errorCorrupt), findsOneWidget);
    // Pesan lengkap TERTAMPIL (bukan ellipsis) — body penuh ditemukan.
    expect(find.text(longMessage), findsOneWidget);
  });

  testWidgets('tombol "Show full error" → dialog berisi pesan penuh',
      (tester) async {
    final longMessage = 'Pesan error yang sangat panjang sekali melebihi '
        'tiga baris tampilan ringkas pada kartu file.';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: JobErrorView(job: job(errorType: 'noText', errorMessage: longMessage))),
    ));

    await tester.tap(find.text(Strings.showFullError));
    await tester.pumpAndSettle(); // dialog — aman (bukan viewer skeleton)

    expect(find.text(longMessage), findsWidgets); // di dialog
    expect(find.byType(SelectableText), findsWidgets);
  });

  testWidgets('tanpa errorMessage → fallback ke judul mapping', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: JobErrorView(job: job(errorType: 'encrypted'))),
    ));
    expect(find.text(Strings.errorEncrypted), findsWidgets);
  });

  testWidgets('errorType tidak dikenal → errorGeneric (dengan %s terisi)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: JobErrorView(job: job(errorType: 'weird'))),
    ));
    // errorGeneric = 'Something went wrong: %s' → %s diganti errorType.
    expect(find.text('Something went wrong: weird'), findsOneWidget);
  });
}
