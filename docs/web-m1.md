# Web Platform — Milestone Status

## M1 — Scaffold (selesai 2026-08-05)

## Hasil

- `flutter create --platforms=web .` → `web/` (index.html, manifest.json, icons, favicon)
- `flutter build web` **SUKSES** (105 s, release)
  - `main.dart.js` 2.0 MB
  - `pdfium.wasm` 5.1 MB + `pdfium_worker.js` 104 KB + `pdfium_client.js` ter-bundle otomatis di `assets/packages/pdfrx/assets/` (default `Pdfrx.pdfiumWasmModulesUrl`)
  - Font asset tree-shaken
- **Temuan penting**: dart2js mengizinkan import `dart:io`/`dart:isolate` (stub) — compile OK, tapi semua API melempar `UnsupportedError` saat RUNTIME. Artinya baseline web build jalan, namun konversi nyata akan gagal (File.write, Isolate.spawn).

## Implikasi untuk M2–M6

| Lapisan | Perilaku web saat ini (baseline) | Perlu refactor (milestone) |
|---|---|---|
| `Converter` (File `.partial`/rename) | Runtime UnsupportedError | M2: MdSink + OutputTarget |
| `IsolateConversionController` (Isolate.spawn) | Runtime UnsupportedError | M3: ConversionExecutor + InlineExecutor |
| `PdfrxSource.open(path)` | Tidak ada path di web | M4: PdfInput bytes + openData |
| FileCard/ResultPanel (File, Platform) | Runtime UnsupportedError | M4/M6 |
| Overwrite check, open folder | Tidak relevan web | M6 |

## Catatan

- Reference machine & build metrics di atas untuk baseline size tracking (M11 deploy).
- `web/index.html` masih default Flutter — diubah di M5 (meta, splash).

## M2 — Output Abstraction (selesai 2026-08-05)

- Baru: \lib/core/output.dart\ — \MdSink\ (FileMdSink/MemoryMdSink), \OutputTarget\ (FileOutput/MemoryOutput)
- \MarkdownWriter\ terima \MdSink\ (bukan IOSink); \Converter.convert\ terima \OutputTarget\ (bukan outputPath)
- Semantik .partial + rename + abort dipindah ke FileOutput; MemoryOutput untuk web (StringBuffer)
- \ConversionResult.outputPath\ jadi nullable (null untuk web)
- \lib/core/converter.dart\ & \markdown_writer.dart\ BEBAS dart:io ✓
- Test: +6 (MemoryOutput convert, output_test FileOutput/MemoryOutput commit/abort, MemoryMdSink) — 50 hijau
- Build Windows OK; benchmark/run_corpus diadaptasi ke FileOutput

## M3 — Execution Abstraction (selesai 2026-08-05)

- Baru: \conversion_executor.dart\ (interface + JobExecutionResult), \isolate_executor.dart\ (worker persist — logika dipindah dari controller), \inline_executor.dart\ (web, pipeline di main isolate), factory conditional import (\_io\/\_web\/\_stub\)
- \IsolateConversionController\ → \BatchConversionController\ — controller TIDAK lagi memegang isolate logic; hanya orchestrasi queue + delegate ke executor
- Web path (factory_web + inline_executor) BEBAS dart:isolate/dart:io ✓ — \lutter build web\ sukses
- Test: +3 InlineExecutor (convert bytes, cancel, corrupt) — 53 hijau; integration desktop tetap pakai IsolateExecutor via factory

## M4 — Input Abstraction (selesai 2026-08-05)

- Baru: \models/pdf_input.dart\ — PdfInput {name, sizeBytes, path (desktop) | bytes (web)}, dedupeKey, outputName
- \QueuedFile\ simpan \PdfInput\ (bukan pdfPath); outputPath = path→.md (desktop) / name→.md (web)
- \ddFiles(List<PdfInput>)\; probe: probePageCountData(bytes) untuk web, probePageCount(path) untuk desktop
- \PdfrxSource.probePageCountData(Uint8List)\ baru
- \pickPdfFiles()\ → List<PdfInput>: kIsWeb → readAsBytes; desktop → path
- \FileCard\ pakai input.sizeBytes (hapus File(path)); overwrite check di-skip di web (kIsWeb)
- \lib/ui/\ bebas File() untuk input ✓; 53 test hijau; build Windows & web sukses

## M5 — Web Config & pdfrx Init (selesai 2026-08-05)

- \main.dart\: panggil \pdfrxFlutterInitialize()\ sebelum runApp (idempotent; desktop: cache dir, web: WASM engine worker)
- \web/index.html\: meta description, theme-color (\#274C8A), splash loading (wordmark + spinner, hidden via flutter-first-frame event)
- \web/manifest.json\: nama 'pdflow — PDF to Markdown', warna ink/paper, orientation any
- Verifikasi build: pdfium.wasm 5.1 MB ter-bundle; serve lokal → index 200, wasm 200 MIME application/wasm ✓
- 53 test hijau
