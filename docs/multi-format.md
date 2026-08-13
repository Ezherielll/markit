# Multi-Format — Implementation Status

Status: **Phase 1 COMPLETED** · Date: 2026-08-06 · Plan revision: `docs/multi-format-plan.md` (v1.1)

## Summary

MarkIt converts formats beyond PDF: TXT/MD/CSV/JSON/XML/HTML → Markdown,
implemented entirely in pure Dart (offline, desktop **and** web). Rebranded app to **MarkIt** (package `markit`, base-href `/MarkIt/`,
GitHub repo `Ezherielll/MarkIt`).

## Supported Formats (Phase 1)

| Format | Extractors | Behavior |
|---|---|---|
| PDF | Existing heuristic pipeline | Streaming via path (desktop) / bytes (web) |
| TXT | `TextExtractor` | BOM strip, UTF-8/latin1, empty lines = paragraphs |
| MD/Markdown | `TextExtractor` | Passthrough if containing markdown syntax |
| CSV | `CsvExtractor` | Quoted fields, CRLF → markdown table (header + separator) |
| JSON | `JsonExtractor` | Parse validation → pretty-printed ` ```json ` |
| XML | `XmlExtractor` | Validation → indented ` ```xml ` |
| HTML | `HtmlExtractor` | h1–h6→heading, p→paragraph, ul/ol→list, table→md table, blockquote→quote, pre/code→code block, a→text(URL); text fallback |

Phase 2–3 roadmap: DOCX · EPUB · XLSX · PPTX · ZIP · Image/Audio EXIF.
OCR & transcription: deferred. YouTube/URL: not supported.

## Architecture

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
  probe PDF only (semantic = per-item progress during conversion),
  drop URL → SnackBar "requires internet — not supported"

## Verification

- `flutter analyze` — 0 issues
- `flutter test` — all tests green
- Windows release build OK · Web build `--base-href /MarkIt/` OK
- GitHub Pages deploy: `https://ezherielll.github.io/MarkIt/`
