# Implementation Plan — Multi-Format Conversion

Status: **COMPLETED (Phase 1)** · Revision: 1.2 · Date: 2026-08-13
Based on: `PRD.md` (performance priorities) · `docs/spike-pdfrx.md` · `docs/web-m1.md`

---

## 1. Executive Summary

This plan expands conversion support beyond PDF to other text and document formats using a **per-type pure-Dart extractor architecture** (offline, running on desktop **and** web).

**Key Decisions:**

| Decision | Result |
|---|---|
| OCR & audio transcription | **Deferred** — desktop-only FFI, large model files, inconsistent accuracy, web incompatible; conflicts with performance priority |
| YouTube URLs (and network URLs) | **Unsupported** — requires network → violates "100% local, zero API" + ToS risk |
| Phase Ordering | **Phase 1**: TXT/MD/CSV/JSON/XML/HTML → **Phase 2**: DOCX/EPUB/XLSX → **Phase 3**: PPTX/ZIP/EXIF |
| Non-PDF Extractor nature | Pure Dart (zero FFI) → consistent offline + cross-platform execution |
| Application Title | **MarkIt** (display title) / **`markit`** (package); tagline **"Convert documents into structured Markdown"** |

---

## 2. Context & Constraints

### 2.1 Feasibility

- Target formats are mostly **ZIP containers + XML** (DOCX/XLSX/PPTX/EPUB) or **plain text / markup** (TXT/MD/CSV/JSON/XML/HTML).
- Core dependencies are available in pure Dart:
  - `archive ^4.0.9` — direct dependency (ZIP unzip; foundation for EPUB/DOCX/XLSX/PPTX)
  - `xml` — transitive dependency → XML parsing
  - `markdown` — transitive dependency → MD rendering
  - `html` — HTML parsing (`html` package)
- Output architecture is fully reusable: `Block`, `MarkdownWriter` (MdSink), `OutputTarget` (File/Memory), `BatchConversionController`, queue UI, ZIP download.

### 2.2 Preserved Constraints

| Constraint | Source |
|---|---|
| 100% local, zero network calls during conversion | Core NFR |
| OCR outside scope | Design rule |
| Performance = priority #1 | Product goals |
| Functional on desktop & web | Platform target |

### 2.3 Explicitly Out of Scope

- **OCR** (Tesseract FFI) — long-term; desktop-only.
- **Audio Transcription** (Whisper.cpp FFI) — long-term; desktop-only.
- **YouTube / URL** — when input is detected as URL (`http://`/`https://`), display message "requires internet — not supported"; file is skipped.
- Images **without OCR** produce EXIF metadata only (Phase 3), not body text.

---

## 3. Architecture

```
PdfInput {path | bytes, name, format}      ← detectFormat (magic bytes + extension)
   → FormatExtractor (lib/core/extractor.dart)
       ├─ PDF → existing pipeline (PdfrxSource → grouper → classifier)
       └─ non-PDF → ExtractorRegistry → MarkdownWriter → OutputTarget
   → IsolateExecutor (desktop worker) / InlineExecutor (web) → queue UI reuse
```

- `lib/core/input_format.dart` — `InputFormat` enum, `detectFormat`, `isUrlName`
- `lib/core/extractors/` — text/csv/json/xml/html + `extractor_registry.dart`
- `MarkdownWriter.writeRaw()` — passthrough/code block/table
- `ConversionExecutor.runJob(format)` — dispatch in worker & inline
- UI: multi-extension picker, per-format icons (`FileCard.iconForFormat`),
  probe PDF only, drop URL → SnackBar "requires internet — not supported"
