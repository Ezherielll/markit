# Implementation Plan — `pdflow`

Status: **approved** — acuan eksekusi development. Berbasis `PRD.md`.

---

## 0. Ringkasan & Asumsi

- Environment: Flutter 3.44.7 stable, Dart 3.12.2, Windows (dev machine). Proyek berisi `PRD.md` + plan ini.
- Target awal: `flutter run -d windows` berjalan.
- Pendekatan: **core pipeline = pure Dart tanpa Flutter** (`lib/core/`) agar unit-test cepat; UI tipis di atasnya.
- Keputusan baru di level implementasi (konsisten dengan PRD):
  1. **Resolusi D5 (two-pass murah)**: pass 1 hanya ekstrak text span + fontSize (tanpa layout/bbox) untuk histogram body font (±15–25 ms/hal). Full extraction hanya sekali di pass 2. Budget total ±50–65 ms/hal → 800 hal ≈ 40–52 s (masuk target ≤55 s). Jika overhead terbukti terlalu besar → fallback stats inkremental.
  2. **File parsial = `.partial`**: tulis ke `output.md.partial`, rename saat sukses, hapus saat cancel/gagal (D7).
  3. **Escaping markdown ringan**: garis diawali `#`, `>`, `-`, `*`, `+`, angka+`.`; backtick — agar output tetap valid MD untuk RAG.
  4. Package picker: `file_selector` (official Flutter, ringan) — bukan file_picker, kecuali drag-drop dibutuhkan.

---

## 1. Setup Proyek (Task 0 — ±1 jam)

| # | Task | Detail | Verifikasi |
|---|---|---|---|
| 0.1 | Init git + gitignore | `git init`; .gitignore: `build/`, `.dart_tool/`, `benchmark/results/`, `corpus/pdfs/` | `git status` bersih |
| 0.2 | Scaffold | `flutter create --project-name pdflow --platforms=windows,macos,linux .` (org `com.pdflow`) | Build Windows sukses: `flutter run -d windows` (app kosong tampil) |
| 0.3 | Dependencies | `pubspec.yaml`: `pdfrx` (pin versi stabil), `file_selector`. Dev: `flutter_lints` (default) | `flutter pub get` sukses |
| 0.4 | Struktur folder | Buat kerangka folder §2 + file placeholder | `flutter analyze` 0 error |

---

## 2. Struktur Kode

```
lib/
├── main.dart, app.dart, theme.dart
├── i18n/strings.dart              # D10: semua string terpusat (EN primary)
├── models/
│   └── layout.dart                # TextSpan, Line, Paragraph (+ enum BlockType)
├── core/                          # PURE DART — tanpa import Flutter
│   ├── pdf_source.dart            # abstract: open(), pageCount, extractLight(page), extractFull(page), dispose()
│   ├── pdfrx_source.dart          # implementasi pdfrx (PDFium)
│   ├── doc_stats.dart             # pass 1: histogram fontSize → bodyFontSize
│   ├── line_grouper.dart          # stage 2: fragment → baris
│   ├── paragraph_joiner.dart      # stage 3: baris → paragraf (gap statistik)
│   ├── structure_classifier.dart  # stage 4: heading (2-tier) + list
│   ├── markdown_writer.dart       # stage 5: streaming writer + escaping
│   ├── converter.dart             # orkestrasi two-pass + progress callback + cancel flag
│   └── errors.dart                # ConvertError {corrupt, encrypted, noText, pageFailed}
├── isolate/
│   ├── messages.dart              # StartConvert, Progress, Done, Failed, CancelRequest
│   └── convert_isolate.dart       # entry point worker + loop pesan
└── ui/
    ├── home_screen.dart           # pick file → info card → convert/cancel
    ├── progress_panel.dart        # bar, x/y, hal/s, elapsed
    └── result_panel.dart          # stats, preview, open folder, warning scan
benchmark/
├── run_benchmark.dart             # CLI headless (pakai core/ saja)
└── golden_evaluator.dart          # skor F1 paragraf, akurasi heading, recall list, noise
corpus/                            # pdfs/ gitignored; golden/*.md committed
docs/benchmark.md
tool/check_offline.dart            # grep dependency tree: http/socket (NFR offline)
```

Model data (interface internal, `models/layout.dart`):
```dart
class TextSpan { String text; double x0, y0, x1, y1; double fontSize; }
class Line     { List<TextSpan> spans; double get height; String get text; }
enum BlockType { heading, paragraph, listItem }
class Block    { BlockType type; List<String> lines; int headingLevel; }
```

---

## 3. Desain Kunci

### 3.1 Two-pass (D5)
- **Pass 1** (`doc_stats.dart`): loop semua halaman, API ringan pdfrx (text span + fontSize saja) → histogram fontSize → `bodyFontSize` = nilai modus. Juga: jumlah halaman, halaman tanpa teks (feed warning scan, FR-10d).
- **Pass 2** (`converter.dart`): per halaman `extractFull` → line grouper → paragraph joiner → classifier (pakai `bodyFontSize` pass 1) → markdown writer streaming → lepas referensi halaman (FR-02).
- Progress callback: `(page, total, elapsed)` tiap halaman.

### 3.2 Isolate (pemisahan UI)
- `convert_isolate.dart`: buka `PdfDocument` **di dalam worker** (PDFium harus dipakai di isolate yang sama), loop halaman, kirim `Progress` via SendPort.
- Protocol (`messages.dart`):
  - UI → worker: `StartConvert {pdfPath, outPath}`, `CancelRequest`
  - Worker → UI: `Progress {page, total, elapsed}`, `Done {stats}`, `Failed {error, detail}`
- **Cancel**: ReceivePort kedua di worker; dicek tiap halaman (FR-11, batal < 1 s). Hapus `.partial`, kirim `Done(cancelled: true)`.
- **Keamanan**: `finally { document.dispose(); sink.close(); }` — tidak bocor handle (NFR memory).

### 3.3 Error taxonomy (FR-10)
| Kondisi | Deteksi | UX |
|---|---|---|
| Corrupt/unreadable | `PdfDocument.open` throw | Dialog error + log, no crash |
| Encrypted | `PdfDocument.isEncrypted` / open error code | "PDF dipassword — tidak didukung" + log |
| Page gagal parse | exception per halaman | Lanjutkan, catat daftar halaman, tampil di summary |
| Scan/no text | pass 1: 0 teks di ≥95% halaman | Warning "tampaknya hasil scan" (sebelum konversi) |

### 3.4 Streaming writer (FR-07)
- Tulis ke `output.md.partial` via `IOSink`, flush tiap halaman (atau ≥64 KB), `\n` saja (D8, UTF-8 default tanpa BOM di Dart).
- Sukses → rename ke `output.md`. Cancel/fail → hapus `.partial`.
- Konvensi output: heading `# teks`, list `- item`, blok dipisah baris kosong; paragraf antar-halaman tidak pernah digabung; escaping ringan.

### 3.5 Heuristik inti (FR-03..05)
- **Line grouper**: sortir spans by y, cluster dengan toleransi vertikal relatif (gap < 0.6× tinggi baris terdekat) → baris; urut left-to-right (asumsi 1 kolom).
- **Paragraph joiner**: gap antar-baris > median gap × 1.5 → batas paragraf; indent baris pertama sebagai sinyal tambahan.
- **Classifier**: heading jika fontSize baris ≥ bodyFontSize × 1.2 (FR-05, 2-tier). List: karakter awal `•`/`-`/`*`/`o`/`▪` (FR-06), item list berurutan dikelompokkan satu blok.
- Koefisien (1.2×, gap 1.5×) **disentralkan di satu tempat** untuk tuning mudah saat evaluasi korpus → advanced settings di M1 (D9).

---

## 4. Task Breakdown M0 (urutan eksekusi + DoD)

| # | Task | Files | FR | DoD / Verifikasi |
|---|---|---|---|---|
| 1 | **Spike pdfrx API** — verifikasi span API (text, bounds, fontSize), encrypted & corrupt detection, kecepatan ekstraksi di 1 file uji | `core/pdfrx_source.dart` | FR-01/02 | Prototype print: pageCount, spans page 1, error encrypted → tercatat di `docs/` |
| 2 | Model + errors | `models/layout.dart`, `core/errors.dart` | — | Unit test trivial; `flutter analyze` bersih |
| 3 | Pass 1 stats | `core/doc_stats.dart`, `core/pdf_source.dart` | FR-05 | Unit test: histogram sintetik → bodyFontSize benar |
| 4 | Line grouping | `core/line_grouper.dart` | FR-03 | Unit test: fragment sintetik (2 baris, 3 kolom offset) → 2 baris urut benar |
| 5 | Paragraph joining | `core/paragraph_joiner.dart` | FR-04 | Unit test: gap kecil menyatu, gap besar terpisah, indent |
| 6 | Classifier | `core/structure_classifier.dart` | FR-05, FR-06 | Unit test: histogram → heading vs body; bullet → listItem |
| 7 | Markdown writer | `core/markdown_writer.dart` | FR-06, FR-07 | Golden string test: heading/list/paragraf + escaping |
| 8 | Converter orkestrasi (two-pass + progress + cancel flag) | `core/converter.dart` | FR-02..07 | Test: file PDF uji kecil → .md valid; memori stabil per halaman |
| 9 | Isolate wrapper | `isolate/messages.dart`, `isolate/convert_isolate.dart` | FR-08 | Widget test: fake worker kirim Progress → UI update |
| 10 | UI: home + progress + result | `ui/*.dart` | FR-01, FR-08, FR-09, FR-12 | Widget test: alur pick→convert→preview; preview < 1 s |
| 11 | Error handling UI | `ui/` + `core/errors.dart` | FR-10 | Skenario: corrupt, encrypted, scan-warning, partial page → dialog benar, no crash |
| 12 | Cancel flow | converter + isolate + UI | FR-11 | Cancel di halaman 50 → < 1 s, `.partial` hilang |
| 13 | Save flow | UI + writer | FR-12 | Konfirmasi overwrite; file UTF-8/\n (verifikasi byte) |
| 14 | **Korpus awal (8–10 file)** + golden manual | `corpus/` | — | Sesuai D6: buku 1-kolom ×3, heading berlapis ×2, tabel ×2, non-Latin ×1, scan ×1, corrupt ×1 |
| 15 | **Evaluator** | `benchmark/golden_evaluator.dart` | — | Skor: F1 paragraf, akurasi heading, recall list, noise |
| 16 | **Benchmark harness + decision gate** | `benchmark/run_benchmark.dart` | NFR | 800-hal kompleks: ≤55 s, RSS ≤400 MB → SKIP isolate pool; jika gagal → backlog M2 #7 |
| 17 | Polish & review FR-01..12 checklist | seluruh | semua | `flutter analyze` 0, `flutter test` hijau, manual smoke test |

**Urutan eksekusi di sesi (estimasi ±16–18 jam):**
- **Sesi A** (±3 jam): Task 0–3 (setup, spike, stats)
- **Sesi B** (±5 jam): Task 4–8 (pipeline inti + unit test)
- **Sesi C** (±5 jam): Task 9–13 (isolate + UI + error/cancel/save)
- **Sesi D** (±5 jam): Task 14–17 (korpus, evaluator, benchmark, decision gate, polish)

---

## 5. Test Strategy

| Lapisan | Scope | Cara |
|---|---|---|
| Unit (`test/unit/`) | grouper, joiner, classifier, writer, stats | Data sintetik; murni Dart (`package:test`) |
| Widget (`test/widget/`) | alur UI, progress, error dialog | Fake converter service (inject `PdfSource` abstrak) |
| Integrasi golden (`test/golden/`, opt-in `--tags golden`) | file PDF korpus → banding golden | `golden_evaluator.dart`; batas ambang per PRD §4 |
| Benchmark (`benchmark/`) | performa/memori | Headless CLI, hasil → `docs/benchmark.md` + CSV |
| Manual | UX nyata, file besar | Smoke test Windows |

Evaluator: normalisasi output & golden menjadi unit paragraf → ordered match (F1), akurasi level heading, recall list, kehadiran noise. **Batas lulus MVP: F1 paragraf ≥ 0.90 (single-col), heading ≥ 85%, list ≥ 80%.**

---

## 6. M1 — v1 "Kualitas AI" (outline task, 1–2 weekend)

| Task | FR | Catatan desain |
|---|---|---|
| Filter header/footer | FR-20 | Buffer **hanya baris zona margin** (atas/bawah 8–12%) per halaman (bounded memori ±<1 MB untuk 800 hal); pola di ≥70% halaman → buang; nomor halaman = pola angka murni posisi konsisten; flush keputusan di akhir |
| Heading multi-tier | FR-21 | Bucketing histogram: body → 2–3 bucket di atasnya (H1–H3) |
| Quality warnings | FR-24 | Heuristik: gap-x konsisten → "kemungkinan multi-kolom", halaman tanpa teks, proporsi font aneh; dialog pra-save + summary; skor 0–100 opsional |
| Advanced settings | D9 | Override koefisien heading/gap |
| Ekspansi korpus | D6 | +2 paper 2-kolom (ukur baseline warning) |

**Exit M1:** noise ≤ 1/100 hal; heading ≥ 90%; warning multi-kolom benar ≥ 90%; throughput ≥ 20 hal/s.

---

## 7. M2 — v2 "Konten lengkap" (outline, 2–4 weekend)

- FR-22 multi-kolom (x-clustering sebelum line grouper; reading order kolom-per-kolom) · FR-25 ekstraksi gambar (render per bbox → `_images/pdflow_<page>_<n>.png`, sisipkan `![]()`, tulis langsung ke disk) · FR-23 tabel sederhana (grid detection; merged cells → fallback + warning) · opsional FR-26 split bab, FR-27 front matter, batch mode · kondisional: isolate pool (#7) hanya jika decision gate M0 gagal.

---

## 8. Risiko Implementasi & Mitigasi

| Risiko | Mitigasi |
|---|---|
| API pdfrx tidak cukup detail (span/fontSize/bbox) | Task 1 spike di depan; cadangan: `pdf_text` (parsing manual, lebih lambat) — keputusan di spike |
| Two-pass melewati budget waktu | Fallback stats inkremental (PRD D5); diukur task 16 |
| PDFium di isolate (thread-safety, handle per isolate) | Buka document di dalam worker; dispose di `finally`; test konversi berturut-turut |
| Overhead CI di weekend | Prioritas: analyze + test lokal; CI optional |
| Golden corpus bias | D6: dokumentasi reference machine; catat semua angka mentah |
