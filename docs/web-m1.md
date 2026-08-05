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

- `main.dart`: panggil `pdfrxFlutterInitialize()` sebelum runApp (idempotent; desktop: cache dir, web: WASM engine worker)
- `web/index.html`: meta description, theme-color (#274C8A), splash loading (wordmark + spinner, hidden via flutter-first-frame event)
- `web/manifest.json`: nama 'pdflow — PDF to Markdown', warna ink/paper, orientation any
- Verifikasi build: pdfium.wasm 5.1 MB ter-bundle; serve lokal → index 200, wasm 200 MIME application/wasm ✓
- 53 test hijau

## M6 — Responsive UI + Download + Drop Fallback (selesai 2026-08-05)

- Baru: `ui/download_text.dart` (conditional import) — web: Blob + anchor download via dart:js_interop; desktop: no-op (file sudah di disk)
- `ResultPanel` refactor: terima `QueuedFile`; konten dari memory (web) / file (desktop); aksi adaptif — web: Download; desktop: Open folder + Copy path; preview + stat chips tetap (FR-09)
- `_SummaryState`: tampilkan ResultPanel untuk file sukses pertama di bawah daftar status
- `DropZone._onDrop`: fallback web — fileUri tidak tersedia → coba plainText uri-list; gagal → SnackBar arahkan ke picker
- Dep baru: `web` (dart:js_interop untuk download)
- 53 test hijau (+1 assertion FR-09); build Windows & web sukses

## M7 — Theme Switcher (selesai 2026-08-05)

- Baru: `theme/theme_controller.dart` — ThemeMode (light/dark/system), cycle, persist via SharedPreferences (desktop disk / web localStorage)
- `main.dart`: load pref sebelum runApp; `PdflowApp` stateful + ListenableBuilder(themeMode); `AppHeader` tombol cycle dengan ikon adaptif (light/dark/auto)
- Dep baru: `shared_preferences`
- 57 test hijau (+3 unit ThemeController: cycle, persist-reload, fallback; +1 widget: toggle cycle); build Windows & web sukses

## M8 — Routing Check (selesai 2026-08-05)

- Aplikasi single-screen tanpa router/navigator manual → TIDAK perlu go_router.
- Flutter web default: hash routing (`#/`) + `base href="/"` — aman untuk deploy root maupun sub-path (M11 `--base-href`).
- State ephemeral (queue batch) wajar hilang saat refresh browser — tidak ada deep-link yang perlu dipertahankan.
- Future (opsional): `?pdf=` param untuk deep-link — dicatat, bukan sekarang.

## M9 — Asset & Environment (selesai 2026-08-05)

- Font (Fraunces/Inter/JetBrainsMono) ter-bundle & ter-verifikasi di `build/web/assets/assets/fonts/` (total ~1.4 MB) — dimuat dari lokal, tanpa fetch jaringan.
- Tidak ada HTTP client di `lib/` — NFR offline tetap berlaku di web (semua sumber lokal: fonts, pdfium.wasm, main.dart.js).
- Konfigurasi env via `--dart-define` (pola dokumentasi):
  - `Pdfrx.pdfiumWasmModulesUrl` override — hanya jika butuh wasm dari CDN (tidak direkomendasikan; default local bundle).
  - Future config lain (mis. analitik lokal) — pakai `String.fromEnvironment`.
- Catatan bundle web (release): main.dart.js ~2 MB + pdfium.wasm 5.1 MB + fonts 1.4 MB — loading splash (M5) menutupi inisialisasi awal.

## M10 — Testing (selesai 2026-08-05)

- `flutter analyze` 0 issue; `flutter test` 57 hijau (unit pipeline, InlineExecutor, theme, output, widget flow).
- Integration test batch di-tag `@Tags(['desktop'])` — memakai IsolateExecutor + dart:io, tidak dijalankan di web test runner.
- Web logic teruji di VM: InlineExecutor (convert bytes / cancel / corrupt), MemoryOutput, download helper (stub path).
- Manual checklist browser — dilakukan di M11 pasca deploy (Chrome + Edge, resize, keyboard, drop).

## M12 — Bug Fixes Web (selesai 2026-08-05)

### Bug #1: download multi-file hanya 1 file
- Penyebab: summary hanya merender 1 ResultPanel (job done pertama) + tombol download per-file.
- Fix: tombol **"Download all as ZIP (N)"** di summary (web) — semua `job.content` done digabung jadi satu ZIP via `package:archive` (Blob download), pola conditional import (`download_zip.dart`/`_web.dart`/`_stub.dart`). Per-file download tetap ada.
- `archive` jadi direct dependency. Test: unit ZIP encode/decode + koleksi job done.

### Bug #2: lambat ganti theme di halaman convert
- Penyebab: `MarkdownBody` meng-parse ulang SELURUH konten tiap rebuild (termasuk toggle theme) — mahal untuk dokumen besar.
- Fix: preview di-truncate di batas baris (max 64 KB, `truncateMarkdownPreview`) + `RepaintBoundary` di sekitar preview + indikator "Preview truncated". Download tetap full content.
- Test: unit truncation (batas baris, baris panjang, konten asli utuh).

- Verifikasi: 63 test hijau; build Windows & web sukses; deploy otomatis via Actions.

## M13 — Conditional Download + Header Redesign (selesai 2026-08-05)

### Download kondisional
- Single file (done == 1): ResultPanel menampilkan tombol **Download** biasa.
- Multi-file (done > 1): preview tetap, tombol Download per-file disembunyikan (`showDownloadButton: false`), tombol **"Download all as ZIP (N)"** di summary.
- `done == 0`: tidak ada tombol download. Test: property `showDownloadButton` true/false.

### Header redesign (premium — Notion/Raycast/Linear-style)
- Komponen terpisah di `lib/ui/widgets/header/` (scalable):
  - `app_header.dart` — komposisi + glass background (BackdropFilter blur 12 + surface translucent 0.72–0.78) + divider hairline + soft shadow
  - `brand_lockup.dart` — ikon dokumen gradient + "pdflow" (Fraunces) + subtitle "Convert PDFs into structured Markdown"
  - `status_pill.dart` — status kontekstual: Ready / N files loaded / Processing N documents / N converted (dari controller)
  - `header_toolbar.dart` — grup rounded: theme toggle + settings (disabled placeholder) + divider + reset; hover halus, hit area 34×34
- Responsive: `< 900px` subtitle & label pill collapse (Flexible); aksi tetap utuh
- Strings baru: headerSubtitle, status*, settingsTooltip
- Test: +4 status pill, +2 conditional download — 69 hijau

## M11 — Build & Deployment (selesai 2026-08-05)

- Build release web: \lutter build web --release --base-href /pdflow/\ (bundle ±47 MB: main.dart.js ~2 MB + pdfium.wasm 5.1 MB + canvaskit variants)
- **GitHub Pages live**: https://ezherielll.github.io/pdflow/ — deploy otomatis via Actions (\.github/workflows/deploy-web.yml\), verifikasi index 200 + pdfium.wasm 200 MIME application/wasm
- Docs: \docs/web-deploy.md\; README section Web
- **Git Flow**: branch \develop\ dibuat dari master (integration); tag \1.1.0-web\ di master
- 57 test hijau; analyze 0
