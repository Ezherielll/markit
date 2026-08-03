# M0 Exit Criteria — Checklist FR-01..12

Status: 2026-08-03 (implementasi M0 selesai)

| FR | Requirement | Status | Bukti |
|---|---|---|---|
| FR-01 | Pilih file PDF + jumlah halaman < 2 s | ✅ | `probePageCount` (pdfrx metadata); picker `file_selector` |
| FR-02 | Ekstraksi fragment per halaman, tanpa accumulate | ✅ | `PdfrxSource.loadFull` per halaman; benchmark delta RSS 10 MB untuk 800 hal |
| FR-03 | Grouping baris (y-clustering, LTR) | ✅ | `LineGrouper` + unit test (4 test) |
| FR-04 | Penggabungan paragraf (gap statistik) | ✅ | `ParagraphJoiner` (median-of-small-gaps × faktor) + unit test |
| FR-05 | Klasifikasi heading (stats-based, bukan hardcode) | ✅ | `DocStatsComputer` histogram bucket 0.5pt + windowed mode; `StructureClassifier` |
| FR-06 | Deteksi list bullet sederhana | ✅ | Classifier: bullet per baris, continuation line menyambung |
| FR-07 | Output streaming per halaman | ✅ | `MarkdownWriter` + flush per halaman; UTF-8 no BOM, `\n` (teruji byte-level) |
| FR-08 | UI progress + statistik | ✅ | `ProgressPanel` (%, x/y, elapsed, pages/s) via controller ChangeNotifier |
| FR-09 | Preview hasil + stats struktur | ✅ | `ResultPanel` (preview 64KB, hitung heading/paragraf/list) |
| FR-10 | Error handling: corrupt/encrypted/noText/pageFailed | ✅ | `mapOpenError` (PdfPasswordException → encrypted), `likelyScanned` (≥95% kosong → noText), failedPages collect; widget test |
| FR-11 | Cancel: batal < 1 s, `.partial` dihapus | ✅ | `CancelRequest` via isolate; converter cleanup; unit + widget test |
| FR-12 | Simpan output + konfirmasi overwrite | ✅ | Dialog overwrite di `_convert`; rename dari `.partial` |

## Hasil korpus & benchmark

- **book_single (60 hal, single-column)**: F1 paragraf **100%**, heading 100%, list 100%, noise 0 → lulus ambang M0 (≥ 0.90). Lihat `docs/benchmark.md`.
- **with_tables**: F1 28.6% — sesuai ekspektasi PRD §8 (tabel = baseline v2, FR-23).
- **Decision gate performa (800 hal sintetis)**: 7.8 s total, delta RSS 10 MB → **isolate pool SKIP**.

## Keputusan teknis yang terkonfirmasi saat implementasi

1. pdfrx 2.4.7 **tidak punya API fontSize** → proxy tinggi bbox char/baris (skala sama pass1/pass2). Lihat `docs/spike-pdfrx.md`.
2. Two-pass (D5): pass1 `loadText` (histogram line-height) ≈ 570 ms; pass2 ≈ 7.3 s untuk 800 hal — overhead pass1 < 8%, layak.
3. ParagraphJoiner pakai median gap *kecil* (di bawah median pertama) — median semua gap terbukti salah karena tercemar gap antar-paragraf.
4. Isolate worker: PDFium harus dibuka **di dalam** isolate worker (handle per-isolate).

## Sisa untuk M0 lengkap (backlog kecil)

- Korpus ekspansi (non-Latin, scan-warning, corrupt, encrypted) — Task 14 lanjutan.
- Golden evaluator: metrik noise & heading-level diperhalus (saat ini heading accuracy = recall level-1).
- Smoke test manual `flutter run -d windows` pada file PDF besar nyata.
