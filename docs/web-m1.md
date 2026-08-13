# Web Platform — Milestone Status

## M1 — Scaffold (Completed 2026-08-05)

## Results

- `flutter create --platforms=web .` → `web/` (index.html, manifest.json, icons, favicon)
- `flutter build web` **SUCCESS** (105 s, release)
  - `main.dart.js` 2.0 MB
  - `pdfium.wasm` 5.1 MB + `pdfium_worker.js` 104 KB + `pdfium_client.js` bundled automatically under `assets/packages/pdfrx/assets/` (default `Pdfrx.pdfiumWasmModulesUrl`)
  - Font assets tree-shaken
- **Key finding**: dart2js allows importing `dart:io`/`dart:isolate` (stubs) — compilation succeeds, but all APIs throw `UnsupportedError` at RUNTIME. This means baseline web builds compile, but conversion logic using `File.write` / `Isolate.spawn` will fail.

## Implications for M2–M6

| Layer | Baseline Web Behavior | Required Refactoring |
|---|---|---|
| `Converter` (`.partial`/rename) | Runtime UnsupportedError | M2: MdSink + OutputTarget |
| `IsolateConversionController` (`Isolate.spawn`) | Runtime UnsupportedError | M3: ConversionExecutor + InlineExecutor |
| `PdfrxSource.open(path)` | No file paths on web | M4: PdfInput bytes + openData |
| FileCard/ResultPanel (`File`, `Platform`) | Runtime UnsupportedError | M4/M6 |
| Overwrite check, open folder | Not applicable on web | M6 |

## Notes

- Reference machine & build metrics above for baseline size tracking (M11 deploy).
- `web/index.html` updated for meta and splash.

## M2 — Output Abstraction (Completed 2026-08-05)

- New: `lib/core/output.dart` — `MdSink` (FileMdSink/MemoryMdSink), `OutputTarget` (FileOutput/MemoryOutput)
- `MarkdownWriter` accepts `MdSink` (instead of IOSink); `Converter.convert` accepts `OutputTarget` (instead of outputPath)
- `.partial` + rename + abort semantics moved to FileOutput; MemoryOutput for web (StringBuffer)
- `ConversionResult.outputPath` made nullable (null on web)
- `lib/core/converter.dart` & `markdown_writer.dart` FREE of `dart:io` ✓
- Tests: +6 (MemoryOutput convert, output_test FileOutput/MemoryOutput commit/abort, MemoryMdSink) — all green

## M3 — Execution Abstraction (Completed 2026-08-05)

- New: `conversion_executor.dart` (interface + JobExecutionResult), `isolate_executor.dart` (persistent worker — logic moved from controller), `inline_executor.dart` (web, pipeline on main isolate), conditional import factory (`_io`/`_web`/`_stub`)
- `IsolateConversionController` → `BatchConversionController` — controller NO LONGER handles isolate logic directly; orchestrates queue + delegates to executor
- Web path (factory_web + inline_executor) FREE of `dart:isolate`/`dart:io` ✓ — `flutter build web` succeeds

## M4 — Input Abstraction (Completed 2026-08-05)

- New: `models/pdf_input.dart` — PdfInput {name, sizeBytes, path (desktop) | bytes (web)}, dedupeKey, outputName
- `QueuedFile` stores `PdfInput` (instead of pdfPath); outputPath = path→.md (desktop) / name→.md (web)
- `addFiles(List<PdfInput>)`; probe: probePageCountData(bytes) for web, probePageCount(path) for desktop
- `PdfrxSource.probePageCountData(Uint8List)` added
- `pickPdfFiles()` → List<PdfInput>: kIsWeb → readAsBytes; desktop → path
- `FileCard` uses input.sizeBytes (removed `File(path)`); overwrite check skipped on web (`kIsWeb`)

## M5 — Web Config & pdfrx Init (Completed 2026-08-05)

- `main.dart`: invoke `pdfrxFlutterInitialize()` before runApp (idempotent; desktop: cache dir, web: WASM engine worker)
- `web/index.html`: meta description, theme-color (#274C8A), splash loading (wordmark + spinner)
- `web/manifest.json`: name 'MarkIt — Document to Markdown Converter'

## M6 — Responsive UI + Download + Drop Fallback (Completed 2026-08-05)

- New: `ui/download_text.dart` (conditional import) — web: Blob + anchor download via `dart:js_interop`; desktop: no-op (file on disk)
- `ResultPanel` refactor: accepts `QueuedFile`; content from memory (web) / file (desktop); adaptive action — web: Download; desktop: Open folder + Copy path
- `DropZone._onDrop`: web fallback — fileUri unavailable → plainText uri-list fallback; fails → SnackBar directs user to picker

## M7 — Theme Switcher (Completed 2026-08-05)

- New: `theme/theme_controller.dart` — ThemeMode (light/dark/system), cycle, persist via SharedPreferences (desktop disk / web localStorage)
- `main.dart`: load pref before runApp; `MarkitApp` stateful + ListenableBuilder(themeMode); `AppHeader` cycle button with adaptive icons

## M8 — Routing Check (Completed 2026-08-05)

- Single-screen application without manual router/navigator → `go_router` unnecessary.
- Flutter web default: hash routing (`#/`) + `base href="/MarkIt/"`.

## M9 — Asset & Environment (Completed 2026-08-05)

- Fonts (Fraunces/Inter/JetBrainsMono) bundled & verified in `build/web/assets/assets/fonts/` (total ~1.4 MB) — loaded locally, zero network fetches.
- Zero HTTP clients in `lib/` — offline NFR holds on web (all local assets: fonts, pdfium.wasm, main.dart.js).

## M10 — Testing (Completed 2026-08-05)

- `flutter analyze` 0 issues; `flutter test` green.
- Batch integration tests tagged `@Tags(['desktop'])`.

## M12 — Bug Fixes Web (Completed 2026-08-05)

### Bug #1: Multi-file download only downloaded 1 file
- Fix: **"Download all as ZIP (N)"** button in summary (web) — aggregates all completed `job.content` into a single ZIP via `package:archive` (Blob download).

### Bug #2: Slow theme switching on conversion page
- Fix: preview truncated at line boundaries (max 64 KB, `truncateMarkdownPreview`) + `RepaintBoundary` around preview + "Preview truncated" indicator. Download retains full content.

## M14 — Concurrent Conversion (Completed 2026-08-06)

- `IsolateExecutor` routing per-jobId (Map completer+progress, persistent handler).
- `convertAll()` parallel (`Future.wait` all queued jobs); per-job progress in `QueuedFile`.

## M13 — Conditional Download + Header Redesign (Completed 2026-08-05)

- Single file (done == 1): ResultPanel displays standard **Download** button.
- Multi-file (done > 1): **"Download all as ZIP (N)"** button in summary.
- Header redesign: glass background (BackdropFilter blur 12) + brand lockup ("MarkIt", Fraunces font).

## M11 — Build & Deployment (Completed 2026-08-05)

- Web release build: `flutter build web --release --base-href /MarkIt/`
- **GitHub Pages live**: https://ezherielll.github.io/MarkIt/
- Docs: `docs/web-deploy.md`; README section Web
