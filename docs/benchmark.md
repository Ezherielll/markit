# Benchmark — pdflow M0

Reference machine: Windows 11 · i5/i7-class · 16 GB RAM · NVMe SSD (D6)
Tanggal: 2026-08-03

## Decision gate M0 (PRD §11): isolate pool

| Metrik | Target | Hasil (800 hal, PDF sintetis) | Status |
|---|---|---|---|
| Total waktu (pass1+pass2) | ≤ 55 s | **7.8 s** (avg 0.9 ms/hal, p95 3 ms) | ✅ PASS |
| Memori (delta RSS selama pass 2) | ≤ 100 MB | **10 MB** | ✅ PASS |
| Peak RSS proses | ≤ 400 MB | 379 MB (termasuk baseline VM+engine 494 MB; angka OS) | ✅ PASS |

**Keputusan: isolate pool SKIP** — single-thread + streaming write cukup cepat
untuk MVP. Backlog v2 #7 hanya jika benchmark dengan korpus nyata (gambar/tabel)
menunjukkan degradasi.

Catatan:
- PDF sintetis (factory) tanpa gambar/tabel — angka sebenarnya pada dokumen
  kompleks bisa lebih tinggi; wajib divalidasi ulang di korpus nyata (Task 14/16).
- pass1 (loadText) jauh lebih murah dari pass2 (structuredText+write): 570 ms vs
  7.3 s → two-pass (D5) terbukti layak, overhead pass1 < 8%.
- RSS OS tidak stabil (±100 MB jitter) — metrik memory memakai delta selama pass2.

## Raw data
`benchmark/results/*.csv` (gitignored)

## Corpus run 2026-08-03T15:34:36.247711
- book_single: F1 0.0% (threshold 1%) FAIL · 565 ms
- with_tables: F1 0.0% (threshold 1%) FAIL · 10 ms

## Corpus run 2026-08-03T15:46:01.666429
- book_single: F1 0.0% (threshold 1%) FAIL · 1183 ms
- with_tables: F1 0.0% (threshold 1%) FAIL · 38 ms

## Corpus run 2026-08-03T15:47:28.295520
- book_single: F1 0.0% (threshold 1%) FAIL · 802 ms
- with_tables: F1 0.0% (threshold 1%) FAIL · 9 ms

## Corpus run 2026-08-03T15:49:04.747814
- book_single: F1 0.0% (threshold 1%) FAIL · 573 ms
- with_tables: F1 0.0% (threshold 1%) FAIL · 9 ms

## Corpus run 2026-08-03T15:49:33.935979
- book_single: F1 0.0% (threshold 1%) FAIL · 508 ms

## Corpus run 2026-08-03T15:50:53.093616
- book_single: F1 1.0% (threshold 1%) PASS · 660 ms
- with_tables: F1 0.3% (threshold 1%) FAIL · 7 ms

## Corpus run 2026-08-03T15:51:28.100097
- book_single: F1 100.0% (threshold 90%) PASS · 749 ms
- with_tables: F1 28.6% (threshold 60%) FAIL · 8 ms

## Corpus run 2026-08-03T15:53:07.616186
- book_single: F1 100.0% (threshold 90%) PASS · 598 ms
- with_tables: F1 28.6% (threshold 60%) FAIL · 6 ms

## Corpus run 2026-08-05T11:38:41.957016
- book_single: F1 100.0% (threshold 90%) PASS · 579 ms
- with_tables: F1 28.6% (threshold 60%) FAIL · 26 ms

## Corpus run 2026-08-12T17:40:53.701840
- book_single: paragraphF1 100.0% (threshold 90%) PASS · 449 ms
- nested_headings: headingLevelF1 100.0% (threshold 85%) PASS · 11 ms
- numbered_sections: headingLevelF1 100.0% (threshold 80%) PASS · 9 ms
- ordered_list: orderedListPrecision 100.0% (threshold 80%) PASS · 9 ms
- with_tables: paragraphF1 28.6% (threshold 60%) FAIL · 7 ms

## Corpus run 2026-08-12T17:41:09.582920
- book_single: paragraphF1 100.0% (threshold 90%) PASS · 487 ms
- nested_headings: headingLevelF1 100.0% (threshold 85%) PASS · 16 ms
- numbered_sections: headingLevelF1 100.0% (threshold 80%) PASS · 11 ms
- ordered_list: orderedListPrecision 100.0% (threshold 80%) PASS · 11 ms
- with_tables: paragraphF1 28.6% (threshold 60%) FAIL · 7 ms

## Corpus run 2026-08-12T18:11:18.187914
- book_single: paragraphF1 100.0% (threshold 90%) PASS · 719 ms
- header_footer: headerSuppressionRecall 100.0% (threshold 90%) PASS · 11 ms
- multi_column_paper: readingOrderScore 100.0% (threshold 80%) PASS · 13 ms
- nested_headings: headingLevelF1 100.0% (threshold 85%) PASS · 17 ms
- numbered_sections: headingLevelF1 100.0% (threshold 80%) PASS · 20 ms
- ordered_list: orderedListPrecision 100.0% (threshold 80%) PASS · 15 ms
- with_tables: paragraphF1 28.6% (threshold 60%) FAIL · 11 ms

## Corpus run 2026-08-12T22:10:09.285497
- book_single: paragraphF1 100.0% (threshold 90%) PASS · 927 ms
- header_footer: headerSuppressionRecall 100.0% (threshold 90%) PASS · 9 ms
- multi_column_paper: readingOrderScore 100.0% (threshold 80%) PASS · 13 ms
- nested_headings: headingLevelF1 100.0% (threshold 85%) PASS · 15 ms
- nested_list: nestedListRecall 100.0% (threshold 80%) PASS · 8 ms
- numbered_sections: headingLevelF1 100.0% (threshold 80%) PASS · 13 ms
- ordered_list: orderedListPrecision 100.0% (threshold 80%) PASS · 13 ms
- simple_table: tableCellF1 100.0% (threshold 70%) PASS · 15 ms

## Corpus run 2026-08-12T22:10:29.266840
- book_single: paragraphF1 100.0% (threshold 90%) PASS · 785 ms
- header_footer: headerSuppressionRecall 100.0% (threshold 90%) PASS · 9 ms
- multi_column_paper: readingOrderScore 100.0% (threshold 80%) PASS · 14 ms
- nested_headings: headingLevelF1 100.0% (threshold 85%) PASS · 15 ms
- nested_list: nestedListRecall 100.0% (threshold 80%) PASS · 10 ms
- numbered_sections: headingLevelF1 100.0% (threshold 80%) PASS · 15 ms
- ordered_list: orderedListPrecision 100.0% (threshold 80%) PASS · 13 ms
- simple_table: tableCellF1 100.0% (threshold 70%) PASS · 18 ms

## Corpus run 2026-08-12T23:41:09.324207
- nested_list: nestedListRecall 100.0% (threshold 80%) PASS · 581 ms

## Corpus run 2026-08-13T00:13:45.199194
- multi_page_table: tableCellF1 100.0% (threshold 70%) PASS · 902 ms

## Corpus run 2026-08-13T00:17:29.913808
- book_single: paragraphF1 100.0% (threshold 90%) PASS · 742 ms
- header_footer: headerSuppressionRecall 100.0% (threshold 90%) PASS · 30 ms
- multi_column_paper: readingOrderScore 100.0% (threshold 80%) PASS · 43 ms
- multi_page_table: tableCellF1 100.0% (threshold 70%) PASS · 25 ms
- nested_headings: headingLevelF1 100.0% (threshold 85%) PASS · 67 ms
- nested_list: nestedListRecall 100.0% (threshold 80%) PASS · 22 ms
- numbered_sections: headingLevelF1 100.0% (threshold 80%) PASS · 37 ms
- ordered_list: orderedListPrecision 100.0% (threshold 80%) PASS · 25 ms
- simple_table: tableCellF1 100.0% (threshold 70%) PASS · 26 ms

## Corpus run 2026-08-13T00:17:47.222957
- book_single: paragraphF1 100.0% (threshold 90%) PASS · 825 ms
- header_footer: headerSuppressionRecall 100.0% (threshold 90%) PASS · 9 ms
- multi_column_paper: readingOrderScore 100.0% (threshold 80%) PASS · 15 ms
- multi_page_table: tableCellF1 100.0% (threshold 70%) PASS · 19 ms
- nested_headings: headingLevelF1 100.0% (threshold 85%) PASS · 18 ms
- nested_list: nestedListRecall 100.0% (threshold 80%) PASS · 10 ms
- numbered_sections: headingLevelF1 100.0% (threshold 80%) PASS · 17 ms
- ordered_list: orderedListPrecision 100.0% (threshold 80%) PASS · 15 ms
- simple_table: tableCellF1 100.0% (threshold 70%) PASS · 11 ms

## Corpus run 2026-08-13T00:21:19.691637
- multi_page_table: tableCellF1 100.0% (threshold 70%) PASS · 391 ms

## Corpus run 2026-08-13T00:46:22.884031
- mixed_table: tableCellF1 100.0% (threshold 70%) PASS · 384 ms

## Corpus run 2026-08-13T00:50:52.890146
- mixed_table: tableCellF1 100.0% (threshold 70%) PASS · 679 ms

## Corpus run 2026-08-13T00:55:26.375021
- book_single: paragraphF1 100.0% (threshold 90%) PASS · 757 ms
- header_footer: headerSuppressionRecall 100.0% (threshold 90%) PASS · 10 ms
- mixed_table: tableCellF1 100.0% (threshold 70%) PASS · 20 ms
- multi_column_paper: readingOrderScore 100.0% (threshold 80%) PASS · 13 ms
- multi_page_table: tableCellF1 100.0% (threshold 70%) PASS · 13 ms
- nested_headings: headingLevelF1 100.0% (threshold 85%) PASS · 17 ms
- nested_list: nestedListRecall 100.0% (threshold 80%) PASS · 11 ms
- numbered_sections: headingLevelF1 100.0% (threshold 80%) PASS · 18 ms
- ordered_list: orderedListPrecision 100.0% (threshold 80%) PASS · 14 ms
- simple_table: tableCellF1 100.0% (threshold 70%) PASS · 9 ms

## Corpus run 2026-08-13T11:39:20.396761
- book_single: paragraphF1 100.0% (threshold 90%) PASS · 1387 ms
- header_footer: headerSuppressionRecall 100.0% (threshold 90%) PASS · 411 ms
- mixed_table: tableCellF1 100.0% (threshold 70%) PASS · 64 ms
- multi_column_paper: readingOrderScore 100.0% (threshold 80%) PASS · 62 ms
- multi_page_table: tableCellF1 100.0% (threshold 70%) PASS · 55 ms
- nested_headings: headingLevelF1 100.0% (threshold 85%) PASS · 67 ms
- nested_list: nestedListRecall 100.0% (threshold 80%) PASS · 52 ms
- numbered_sections: headingLevelF1 100.0% (threshold 80%) PASS · 47 ms
- ordered_list: orderedListPrecision 100.0% (threshold 80%) PASS · 43 ms
- simple_table: tableCellF1 100.0% (threshold 70%) PASS · 46 ms
