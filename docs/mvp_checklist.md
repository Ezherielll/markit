# M0 Exit Criteria — Checklist FR-01..12

Status: 2026-08-03 (M0 implementation completed)

| FR | Requirement | Status | Evidence |
|---|---|---|---|
| FR-01 | Select PDF file + page count probe < 2 s | ✅ | `probePageCount` (pdfrx metadata); picker `file_selector` |
| FR-02 | Extract fragments per page, zero accumulation | ✅ | `PdfrxSource.loadFull` per page; benchmark delta RSS 10 MB for 800 pages |
| FR-03 | Line grouping (y-clustering, LTR) | ✅ | `LineGrouper` + unit tests |
| FR-04 | Paragraph joining (gap statistic) | ✅ | `ParagraphJoiner` (median-of-small-gaps × factor) + unit tests |
| FR-05 | Heading classification (stats-based, not hardcoded) | ✅ | `DocStatsComputer` histogram bucket 0.5pt + windowed mode; `StructureClassifier` |
| FR-06 | Simple bullet list detection | ✅ | Classifier: per-line bullets, continuation line joining |
| FR-07 | Per-page streaming output | ✅ | `MarkdownWriter` + flush per page; UTF-8 no BOM, `\n` (byte-level verified) |
| FR-08 | UI progress + statistics | ✅ | `ProgressPanel` (%, x/y, elapsed, pages/s) via controller ChangeNotifier |
| FR-09 | Result preview + structure stats | ✅ | `ResultPanel` (64KB preview, heading/paragraph/list counters) |
| FR-10 | Error handling: corrupt/encrypted/noText/pageFailed | ✅ | `mapOpenError` (PdfPasswordException → encrypted), `likelyScanned` (≥95% empty → noText), failedPages collection; widget tests |
| FR-11 | Cancel: cancellation < 1 s, `.partial` cleaned up | ✅ | `CancelRequest` via isolate; converter cleanup; unit + widget tests |
| FR-12 | Save output + overwrite confirmation | ✅ | Overwrite dialog in `_convert`; rename from `.partial` |

## Corpus Results & Benchmarks

- **book_single (60 pages, single-column)**: Paragraph F1 **100%**, heading 100%, list 100%, noise 0 → passed M0 threshold (≥ 0.90). See `docs/benchmark.md`.
- **with_tables**: F1 28.6% — expected (tables = v2 baseline).
- **Performance Decision Gate (800 synthetic pages)**: 7.8 s total, delta RSS 10 MB → **isolate pool SKIPPED**.

## Confirmed Technical Decisions

1. pdfrx 2.4.7 **has no fontSize API** → proxy bbox char height (same scale in pass1 & pass2). See `docs/spike-pdfrx.md`.
2. Two-pass pipeline: pass1 `loadText` (line-height histogram) ≈ 570 ms; pass2 ≈ 7.3 s for 800 pages — pass1 overhead < 8%.
3. ParagraphJoiner uses median of *small* gaps (below initial median) — median of all gaps contaminated by inter-paragraph spacing.
4. Isolate worker: PDFium must be initialized **inside** the worker isolate (handles are per-isolate).
