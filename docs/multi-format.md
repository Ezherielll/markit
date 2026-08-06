# Multi-Format — Status Implementasi

Status: **Fase 1 SELESAI** · Tanggal: 2026-08-06 · Revisi plan: `docs/multi-format-plan.md` (v1.1)

## Ringkasan

MarkIt kini mengonversi lebih dari PDF: TXT/MD/CSV/JSON/XML/HTML → Markdown,
murni pure-Dart (offline, desktop **dan** web). Eksekusi paralel dengan
rebrand `pdflow` → **MarkIt** (package `markit`, base-href `/markit/`,
repo GitHub `Ezherielll/markit`).

## Format didukung (Fase 1)

| Format | Extractors | Perilaku |
|---|---|---|
| PDF | Pipeline heuristic existing | Streaming via path (desktop) / bytes (web) |
| TXT | `TextExtractor` | BOM strip, UTF-8/latin1, baris kosong = paragraf |
| MD/Markdown | `TextExtractor` | Passthrough bila mengandung sintaks markdown |
| CSV | `CsvExtractor` | Quoted field, CRLF → tabel markdown (header + separator) |
| JSON | `JsonExtractor` | Validasi parse → pretty-print ` ```json ` |
| XML | `XmlExtractor` | Validasi → indented ` ```xml ` |
| HTML | `HtmlExtractor` | h1–h6→heading, p→paragraph, ul/ol→list, table→tabel md, blockquote→quote, pre/code→code block, a→teks(URL); fallback teks |

Fase 2–3 roadmap: DOCX · EPUB · XLSX · PPTX · ZIP · Image/Audio EXIF.
OCR & transkripsi: ditunda. YouTube/URL: tidak didukung (NG3).

## Arsitektur

```
PdfInput {path | bytes, name, format}      ← detectFormat (magic bytes + ekstensi)
   → FormatExtractor (lib/core/extractor.dart)
       ├─ PDF → pipeline existing (PdfrxSource → grouper → classifier)
       └─ non-PDF → ExtractorRegistry → MarkdownWriter → OutputTarget
   → IsolateExecutor (desktop worker) / InlineExecutor (web) → queue UI reuse
```

- `lib/core/input_format.dart` — `InputFormat` enum, `detectFormat`, `isUrlName`
- `lib/core/extractors/` — text/csv/json/xml/html + `extractor_registry.dart`
- `MarkdownWriter.writeRaw()` — passthrough/code block/tabel (baru)
- `ConversionExecutor.runJob(format)` — dispatch di worker & inline
- UI: picker multi-ekstensi, ikon per format (`FileCard.iconForFormat`),
  probe hanya PDF (semantic = progress per item saat konversi),
  drop URL → SnackBar "requires internet — not supported"

## Verifikasi

- `flutter analyze` — 0 issues
- `flutter test` — **127 hijau** (81 existing + 46 baru: detectFormat 27, extractors 14, inline semantic 5)
- Build Windows release OK · build web `--base-href /markit/` OK
- Deploy GitHub Pages: `https://ezherielll.github.io/markit/` (rebrand)
