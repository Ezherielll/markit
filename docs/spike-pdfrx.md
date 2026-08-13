# pdfrx API Spike — Results & Decisions

Date: 2026-08-03 · Package: `pdfrx 2.4.7` + `pdfrx_engine 0.4.6` + `pdfium_dart 0.2.5`

## Findings

### 1. API Changes from Legacy Documentation (pdfrx 1.x)
- **No `doc.loadPage()` / `page.dispose()`**. Currently: `doc.pages` (List, 1-based), directly accessed via `doc.pages[i]`.
- Text extraction:
  - `page.loadText()` → `PdfPageRawText?` (`fullText` + `charRects` per char) — **lightest footprint**.
  - `page.loadStructuredText()` → `PdfPageText` (`fullText`, `charRects`, `fragments`) — fragments = words/runs with `bounds`, `charRects`, `direction`; built-in line segmentation (`fullText` contains `\n`).
- `PdfDocument.openFile(path)` and `doc.isEncrypted` remain unchanged.
- Coordinate system: `PdfRect(left, top, right, bottom)`, **bottom-left origin**, Y increases upwards. (Note: Y must be flipped during line grouping.)

### 2. NO fontSize API in pdfrx 2.x ❗
- `PdfPageTextFragment` only provides text/bounds/charRects — no font size.
- **Selected solution (MVP): fontSize proxy = bounding box char height.** Validated: 18pt heading → maxCharH 16.97, 12pt body → 11.36; font size ratios across levels are preserved (1.5x vs 1.49x), sufficient for mode statistics and relative classification.
- High-precision backup: `FPDFText_GetFontSize` is available in `pdfium_dart` bindings + `doc.useNativeDocumentHandle` — to be evaluated if the proxy proves insufficient.

### 3. Error Handling
- Corrupt/random PDF → `PdfPasswordException` during `openFile` (PDFium interprets random bytes as encrypted). Implication: error detection must distinguish:
  - `PdfPasswordException` → "encrypted/protected"
  - Other errors from `openFile` → corrupt/unreadable
- Further verification required: true encrypted PDFs vs pure corrupt files.

### 4. Performance (3-Page Synthetic File, Windows)
- `openFile`: ~240 ms (including FFI PDFium initialization)
- `loadStructuredText` per page: ~1.3 ms (small file; realistic figure from user prototype: ~42 ms/page)
- `loadText` is cheaper than `loadStructuredText` → ideal for pass 1 (histogram) without full layout extraction.

## Impact on Pipeline Design

| Original Plan | Adjustment |
|---|---|
| Fragment: `{text, x0, y0, x1, y1, fontSize}` | Preserved; fontSize populated with proxy (max char height fragment). Y-flip from bottom-left → top-left |
| Stage 1 using pdfrx span API | `loadStructuredText()` → fragments (bounds + text); pass 1 uses `loadText()` (without layout) for histogram |
| Stage 2 manual line grouping | Remained manual from fragment bounds (for heuristic control), even though pdfrx provides line breaks in fullText — fragment bounds offer greater detail |
| `PdfException` for corrupt files | Differentiated `PdfPasswordException` (encrypted) vs other errors (corrupt) |

## Status
- ✅ Synthetic PDF factory validated
- ✅ API surface validated (open, pages, isEncrypted, structuredText, loadText, timing)
- ✅ Decision: pdfrx 2.4.7 CONTINUES to be used; fontSize proxy via char height
- Y-flip decision: PDF coordinates bottom-left; line grouping uses native PDF Y and flips when necessary

## Additional Findings (Multi-File Batch, 2026-08)

1. **PDFium is unsafe to repeatedly spawn/teardown within a single process.**
   - Symptom: second worker (subsequent batch) crashes with `Cannot invoke native callback from a different isolate` — pdfrx creates an internal `PdfrxEngineWorker` (FFI isolate) that lives alongside.
   - Solution: **ONE PERSISTENT worker isolate for the entire app lifecycle** (`IsolateConversionController`), subsequent batches reuse the worker + `ResetCancel`.
2. **Page count probe (PDFium on main isolate) MUST ONLY happen BEFORE the first worker is spawned.** Once the worker is running, two concurrent engine workers cause the same crash. Afterwards, pageCount is filled from `ConvertDone.pageCount`.
3. Worker must invoke `source.dispose()` before a job completes — per-job native PDFium handles must be released.
4. `PdfrxEntryFunctions.instance.stopBackgroundWorker()` exists but does not solve teardown issues — persistent-worker approach is safer.

## Additional Findings (Concurrent Conversion, 2026-08-06)

1. **PDFium is SAFE for multi-document processing within ONE worker isolate** (contrary to initial assumptions regarding multi-isolate).
   - Spike validated: 3 & 6 documents opened + converted CONCURRENTLY inside a single worker — zero crashes, delta RSS 1–12 MB.
   - Remaining constraint: DO NOT spawn/teardown multiple isolates (crashes), but multiple documents inside a single persistent isolate = safe.
2. **`commandPort.listen` async callback = concurrent-safe** — each `_runJob` executes in parallel on the same isolate; no manual serialization required.
3. **Per-jobId Routing**: `IsolateExecutor` uses `Map<jobId, _PendingJob>` (completer + onProgress) — one persistent handler distributes worker messages. Previously a single per-job handler caused concurrent jobs to overwrite each other.
4. **Performance Implications**: Concurrency inside a single worker provides I/O overlap + "all running" UX, BUT PDFium FFI remains serialized in `PdfrxEngineWorker` — total wall clock time ≈ sequential. True parallel execution requires multi-isolate support.
