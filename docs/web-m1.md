# Web Platform — M1 Status

Status: 2026-08-05 · Milestone 1 (scaffold) selesai.

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
