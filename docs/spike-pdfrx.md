# Spike pdfrx API — Hasil & Keputusan (Task 1)

Tanggal: 2026-08-03 · paket: `pdfrx 2.4.7` + `pdfrx_engine 0.4.6` + `pdfium_dart 0.2.5`

## Temuan

### 1. API berubah drastis dari dokumentasi lama (pdfrx 1.x)
- **Tidak ada `doc.loadPage()` / `page.dispose()`** lagi. Sekarang: `doc.pages` (List, 1-based), langsung `doc.pages[i]`.
- Ekstraksi teks:
  - `page.loadText()` → `PdfPageRawText?` (`fullText` + `charRects` per char) — **paling ringan**.
  - `page.loadStructuredText()` → `PdfPageText` (`fullText`, `charRects`, `fragments`) — fragments = kata/run dengan `bounds`, `charRects`, `direction`; sudah ada line segmentation (fullText berisi `\n`).
- `PdfDocument.openFile(path)` dan `doc.isEncrypted` tetap ada.
- Koordinat: `PdfRect(left, top, right, bottom)`, **origin bottom-left**, Y ke atas. (Penting: kita perlu flip Y saat grouping baris.)

### 2. TIDAK ada API fontSize di pdfrx 2.x ❗
- `PdfPageTextFragment` hanya punya text/bounds/charRects — tidak ada font size.
- **Solusi terpilih (MVP): proxy fontSize = tinggi bbox char.** Tervalidasi: heading 18pt → maxCharH 16.97, body 12pt → 11.36; rasio antar level terjaga (1.5x vs 1.49x), cukup untuk statistik modus/klasifikasi relatif.
- Cadangan presisi: `FPDFText_GetFontSize` tersedia di `pdfium_dart` bindings + `doc.useNativeDocumentHandle` — dipertimbangkan nanti bila proxy terbukti tidak cukup (m3).

### 3. Error handling
- PDF corrupt/acak → `PdfPasswordException` saat `openFile` (PDFium menginterpretasi bytes acak sebagai encrypted). Implikasi: deteksi harus bedakan:
  - `PdfPasswordException` → "encrypted/protected" (FR-10b)
  - error lain dari openFile → corrupt/unreadable (FR-10a)
- Butuh verifikasi tambahan saat Task 11: PDF encrypted sungguhan vs corrupt murni.

### 4. Performa (file sintetis 3 halaman, Windows)
- `openFile`: ~240 ms (termasuk init FFI PDFium)
- `loadStructuredText` per halaman: ~1.3 ms (file kecil; angka nyata dari prototype user: ~42 ms/halaman)
- loadText lebih murah dari structuredText → cocok untuk pass 1 (histogram) tanpa layout penuh.

## Dampak ke desain pipeline

| Rencana awal | Penyesuaian |
|---|---|
| Fragment: `{text, x0, y0, x1, y1, fontSize}` | Tetap dipakai; fontSize diisi proxy (max char height fragment). Y-flip bottom-left → top-left |
| Stage 1 pakai span API pdfrx | `loadStructuredText()` → fragments (bounds + text); pass 1 pakai `loadText()` (tanpa layout) untuk histogram |
| Stage 2 line grouping manual | Tetap manual dari fragment bounds (untuk kontrol heuristik), walau pdfrx sudah kasih line break di fullText — fragment bounds lebih detail |
| `PdfException` untuk corrupt | Beda `PdfPasswordException` (encrypted) vs error lain (corrupt) |

## Status
- ✅ PDF factory sintetis valid (bug objek numbering ditemukan & diperbaiki: content obj index)
- ✅ API surface tervalidasi (open, pages, isEncrypted, structuredText, loadText, timing)
- ✅ Keputusan: pdfrx 2.4.7 LANJUT dipakai; proxy fontSize via char height
- Keputusan Y-flip: koordinat PDF bottom-left; line grouping akan pakai y-asli PDF lalu di-flip saat perlu — dicatat di `models/layout.dart`
