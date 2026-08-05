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
