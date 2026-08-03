# pdflow

Konverter **PDF → Markdown** untuk desktop (Windows/macOS/Linux) — cepat,
100% lokal, tanpa cloud/API. Target: buku/dokumen besar (ratusan halaman)
menjadi markdown terstruktur (heading/paragraf/list) untuk dibaca, di-index,
dan dipakai sebagai input AI (RAG/LLM).

Dokumen: [PRD](PRD.md) · [Implementation Plan](IMPLEMENTATION_PLAN.md)

## Screenshots

![Empty state](screenshots/empty.png)

![Conversion result](screenshots/done.png)

## Fitur (MVP)

- Ekstraksi teks + layout via pdfrx (PDFium) — single-thread + streaming write
- Klasifikasi struktur berbasis statistik dokumen (bukan threshold hardcoded)
- Heading (2-level), paragraf, list bullet
- Progress per halaman, cancel, error handling (corrupt/encrypted/scan)
- Preview hasil + konfirmasi overwrite
- 100% offline — konversi berjalan di background isolate

## Build & run

```sh
flutter run -d windows        # dev
flutter build windows         # release
```

## Test & benchmark

```sh
flutter analyze
flutter test

# Korpus sintetis + evaluasi golden (butuh pdfrx_engine, pure Dart):
dart run benchmark/make_corpus.dart    # generate PDF + golden (sekali)
dart run benchmark/run_corpus.dart     # convert + evaluasi semua file
dart run benchmark/run_benchmark.dart  # decision gate performa (800 hal default)
```

Hasil benchmark & checklist M0: `docs/benchmark.md`, `docs/mvp_checklist.md`.

## Struktur

```
lib/
  core/     pipeline murni Dart (pdf source, line grouper, joiner,
            classifier, writer, converter) — unit-testable tanpa Flutter
  isolate/  worker isolate + controller (UI tetap responsif)
  models/   TextSpan / Line / Block
  ui/
    screens/     home screen (state machine: empty → selected → running → done)
    widgets/     app header, drop zone, file card, progress panel,
                 result panel (rendered markdown), stat chips
    theme/       palette ink/paper, tipografi (Fraunces/Inter/JetBrains Mono),
                 spacing, PdflowTheme light/dark
assets/fonts/  font bundle (offline-safe)
benchmark/  harness headless + golden evaluator
test/       unit / widget / integration / spike
```

UI "Document Studio": palet kertas & tinta, display serif Fraunces,
preview markdown di-render seperti halaman cetak, drag & drop PDF,
100% offline (font di-bundle sebagai asset).
