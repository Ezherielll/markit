# Rencana Implementasi — Multi-Format Conversion (selain PDF)

Status: **PLANNING — belum dieksekusi** · Revisi: 1.1 · Tanggal: 2026-08-06
Berbasis: `PRD.md` (NG1/NG3/prioritas performa) · `docs/spike-pdfrx.md` · `docs/web-m1.md`
Perubahan 1.1: keputusan **rebrand `pdflow` → `MarkIt`** (package `markit`) — dikerjakan paralel dengan Fase 1; detail §11.

---

## 1. Ringkasan Eksekutif

Aplikasi saat ini hanya mengonversi PDF ke Markdown. Rencana ini memperluas dukungan ke
format teks & dokumen lain dengan arsitektur **extractor per-tipe** yang murni pure-Dart
(offline, jalan di desktop **dan** web).

**Keputusan kunci (locked, hasil diskusi):**

| Keputusan | Hasil |
|---|---|
| OCR (gambar/scan) & transkripsi audio | **Ditunda** — FFI desktop-only, model besar, akurasi variatif, web mustahil; bertentangan prioritas performa |
| YouTube URL (dan URL jaringan umumnya) | **Tidak didukung** — butuh jaringan → melanggar NG3 "100% lokal, nol API" + risiko ToS |
| Urutan fase | **Fase 1**: TXT/MD/CSV/JSON/XML/HTML → **Fase 2**: DOCX/EPUB/XLSX → **Fase 3**: PPTX/ZIP/EXIF |
| Sifat ekstraktor non-PDF | Murni pure-Dart (tanpa FFI) → konsisten offline + lintas platform |
| Rebrand | **`pdflow` → `markit`** (package) / **MarkIt** (display); tagline **"Convert documents into structured Markdown"** — logo/branding kini multi-format, bukan PDF-only. Rename repo GitHub + base-href `/markit/` ikut dieksekusi (detail §11) |

**Estimasi total:** Fase 1 ≈ 6–8 jam kerja (1 weekend). Fase 2–3 = roadmap, belum dijadwalkan.

---

## 2. Konteks & Batasan

### 2.1 Mengapa layak

- Format target mayoritas adalah **kontainer ZIP + XML** (DOCX/XLSX/PPTX/EPUB) atau
  **plain text / markup** (TXT/MD/CSV/JSON/XML/HTML).
- Dependensi inti sudah tersedia & murni Dart (diverifikasi di `pubspec.lock`):
  - `archive ^4.0.9` — **direct dep** (ZIP unzip; juga dasar EPUB/docx/xlsx/pptx)
  - `xml` — transitif (via pdfrx) → parsing dokumen XML
  - `markdown` — transitif → render MD (sudah dipakai UI)
  - `image` — transitif → decode EXIF (Fase 3)
  - `html` — **belum ada di tree** → perlu ditambah di Fase 1 M4 (pure Dart, offline-safe)
- Arsitektur output **sudah reusable**: `Block`, `MarkdownWriter` (MdSink),
  `OutputTarget` (File/Memory), `BatchConversionController`, queue UI, ZIP download —
  tidak perlu ditulis ulang.

### 2.2 Batasan yang dipertahankan

| Batasan | Sumber |
|---|---|
| 100% lokal, nol panggilan jaringan saat konversi | NG3 |
| OCR di luar scope MVP | NG1 |
| Performa = prioritas #1 | PRD §Latar Belakang |
| Berfungsi di desktop & web | Target platform |

### 2.3 Yang TIDAK dikerjakan (eksplisit, dokumentasi roadmap)

- **OCR** (Tesseract FFI) — jangka panjang; desktop-only, perlu disclaimer platform.
- **Transkripsi audio** (Whisper.cpp FFI) — jangka panjang; sama.
- **YouTube / URL** — saat input terdeteksi URL (`http://`/`https://`), tampilkan
  pesan "requires internet — not supported"; file tetap dilewati.
- Gambar **tanpa OCR** hanya menghasilkan metadata EXIF (Fase 3), bukan teks isi.

---

## 3. Arsitektur

### 3.1 Diagram alur

```
PdfInput {path | bytes, name, format}              # format BARU (M1)
   │
   ▼
detectFormat(name, magicBytes)                     # BARU — ekstensi + magic bytes
   │
   ▼
FormatExtractor (per tipe)                         # BARU — interface
   │
   ├── PdfExtractor = pipeline EXISTING
   │     (PdfrxSource → DocStats → LineGrouper → ParagraphJoiner
   │      → StructureClassifier → MarkdownWriter)   # PDF: streaming via path, hemat memori
   │
   └── SemanticExtractor (pure Dart)
         → parse file → List<Block> → MarkdownWriter     # reuse Block/Writer
         → OutputTarget (FileOutput/MemoryOutput)         # reuse
   │
   ▼
BatchConversionController + queue UI + ZIP download      # reuse SEMUA
```

### 3.2 Peta reuse vs baru

| Komponen | Status | Keterangan |
|---|---|---|
| `Block`, `BlockType`, `headingLevel` | ✅ Reuse | Model output sudah umum, dipakai semua extractor |
| `MarkdownWriter` (MdSink) | ✅ Reuse | Streaming per blok, escaping, UTF-8/`\n` |
| `OutputTarget` (FileOutput/MemoryOutput) | ✅ Reuse | Semantik `.partial` + rename + abort |
| `BatchConversionController` | ✅ Reuse | Queue, cancel-all, progress per-job |
| Queue UI, warning, ZIP download | ✅ Reuse | Tanpa perubahan |
| `ConversionExecutor` (isolate/inline) | ⚠️ Adaptasi | Dispatch format sebelum eksekusi |
| `InputFormat` + `detectFormat` | 🆕 Baru | `lib/core/input_format.dart` |
| `FormatExtractor` interface | 🆕 Baru | `lib/core/extractor.dart` |
| Extractor per tipe | 🆕 Baru | `lib/core/extractors/` |
| `PdfInput.format` | 🆕 Baru | Diisi saat `addFiles` |
| UI picker/ikon/probe | 🆕 Penyesuaian | Multi-ekstensi, ikon per format |

---

## 4. Spesifikasi Deteksi Format

### 4.1 `InputFormat`

```dart
enum InputFormat {
  pdf, text, markdown, csv, json, xml, html,
  docx, xlsx, pptx, epub, zip,
  image, audio,
  unknown,
}
```

### 4.2 `detectFormat(String name, Uint8List bytes)` — aturan

| Format | Ekstensi | Magic bytes | Prioritas |
|---|---|---|---|
| pdf | `.pdf` | `%PDF-` | ekstensi / magic |
| text | `.txt` | — | ekstensi |
| markdown | `.md`, `.markdown` | — | ekstensi |
| csv | `.csv` | — | ekstensi |
| json | `.json` | `{` atau `[` (setelah trim whitespace) | ekstensi / magic |
| xml | `.xml` | `<?xml`, `<` | ekstensi / magic |
| html | `.html`, `.htm` | `<!DOCTYPE html`, `<html` | ekstensi / magic |
| docx | `.docx` | `PK\x03\x04` + `[Content_Types].xml` memuat `word/` | magic + ekstensi |
| xlsx | `.xlsx` | `PK` + `[Content_Types].xml` memuat `xl/` | magic + ekstensi |
| pptx | `.pptx` | `PK` + `[Content_Types].xml` memuat `ppt/` | magic + ekstensi |
| epub | `.epub` | `PK` + entry `mimetype` = `application/epub+zip` | magic + ekstensi |
| zip | `.zip` | `PK` (tanpa signature khusus) | magic |
| image | `.jpg, .jpeg, .png, .gif, .webp, .bmp, .tiff` | `\xFF\xD8`, `\x89PNG`, `GIF8`, `RIFF` | ekstensi / magic |
| audio | `.mp3, .flac, .ogg, .wav, .m4a, .aac` | `ID3`, `OggS`, `fLaC`, `RIFF` | ekstensi / magic |
| unknown | lainnya | — | — |

**Catatan penting:**

- ZIP-based (docx/xlsx/pptx/epub) semuanya mulai dari `PK\x03\x04` → pembeda akhir
  adalah **inspeksi konten ZIP** (entry `mimetype` untuk EPUB, `[Content_Types].xml`
  untuk Office) — bukan hanya ekstensi, agar file yang di-rename ekstensinya tetap terdeteksi.
- Deteksi dilakukan **sekali saat `addFiles`** (kecil, hanya baca header + daftar entry ZIP
  level-1), hasil disimpan di `PdfInput.format`.
- URL (name diawali `http://`/`https://`) → `InputFormat.unknown` + flag `isUrl` untuk pesan "not supported".

---

## 5. Spesifikasi FormatExtractor

### 5.1 Interface (baru)

```dart
abstract class FormatExtractor {
  InputFormat get format;

  /// Ekstrak dokumen → tulis blok ke writer (streaming).
  /// bytes: semantic extractor (pure Dart); path: cadangan utk PDF (streaming hemat memori).
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required MarkdownWriter writer,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  });
}

class ExtractionResult {
  final int itemCount;        // halaman (PDF) / blok-item (lainnya); null jika tak diketahui
  final List<String> warnings; // peringatan non-fatal
}
```

### 5.2 Kontrak

- **Error fatal** (file korup/tidak terbaca): lempar `ConvertError` → per-job gagal,
  batch tetap lanjut (perilaku batch existing).
- **Partial content**: bila sebagian bisa dibaca, tulis apa adanya + `warnings`.
- **Cancel**: `isCancelled()` dicek per-blok/item → hentikan & biarkan `OutputTarget` abort.
- **Progress**: `onProgress(done, total)` per item (baris/paragraf/slide) → UI pakai
  mekanisme progress existing (phase label + counter).

### 5.3 Spesifikasi perilaku per extractor (contoh input → output markdown)

| Extractor | Perilaku | Contoh output |
|---|---|---|
| **Text** (txt) | Strip BOM; deteksi UTF-8 (fallback latin1); baris kosong = pemisah paragraf | `Paragraf 1\n\nParagraf 2` |
| **Markdown** (md) | **Passthrough** — tulis isi apa adanya | isi file asli |
| **CSV** | Parse quoted field (`"a,b"` → satu kolom); baris pertama = header | `\| Kolom A \| Kolom B \|\n\| --- \| --- \|\n\| a,b \| c \|` |
| **JSON** | Validasi parse; pretty-print indent 2 → code block | ```` ```json\n{\n  "key": "value"\n}\n``` ```` |
| **XML** | Format indented → code block | ```` ```xml\n<root>...</root>\n``` ```` |
| **HTML** | DOM → blocks: `h1–h6`→heading, `p`→paragraph, `ul/ol/li`→list, `table`→tabel markdown, `blockquote`→quote, `pre/code`→code block, `a`→teks+URL; tanpa struktur → satu blok teks | heading/paragraf/list sesuai DOM |
| **DOCX** (F2) | ZIP+XML: `w:p`→paragraf, `w:pStyle HeadingN`→heading, `w:tbl`→tabel, `w:numPr`→list | urut sesuai alur dokumen |
| **EPUB** (F2) | ZIP: urutkan `spine` dari `content.opf` → tiap chapter XHTML dilempar ke HtmlExtractor | per chapter: heading `# Judul` + isi |
| **XLSX** (F2) | ZIP: `sharedStrings.xml` + tiap `sheet` XML → tabel per sheet | `# Sheet1` + tabel markdown |
| **PPTX** (F3) | ZIP: `ppt/slides/slideN.xml` urut; teks `a:t`; placeholder judul → heading | `# Judul slide` + bullet isi |
| **ZIP** (F3) | Daftar entry; tiap entry teks (txt/md/csv/json/xml/html) diekstrak rekursif 1 level; entry lain dicatat | `## file.txt` + isi |
| **Image EXIF** (F3) | Baca EXIF (make, model, date, GPS, dst) → blok metadata | `# metadata` + tabel key-value |
| **Audio tags** (F3) | ID3v2 (MP3) / Vorbis comment (FLAC/OGG): title, artist, album, year | tabel metadata |

---

## 6. Detail Fase 1 (yang dieksekusi saat plan disetujui)

### M1 — Foundation: deteksi + interface (1–1.5 jam)

| Task | File |
|---|---|
| `enum InputFormat` + `detectFormat(name, bytes)` (+ `isUrl` detect) | `lib/core/input_format.dart` (baru) |
| `abstract FormatExtractor` + `ExtractionResult` | `lib/core/extractor.dart` (baru) |
| `PdfInput.format` — diisi saat `addFiles` | `lib/models/pdf_input.dart` |
| Dispatch di executor: PDF → jalur existing (path/streaming); non-PDF → extractor semantic (worker desktop baca path→bytes; web bytes langsung) | `lib/isolate/isolate_executor.dart`, `inline_executor.dart` |

**DoD M1:** deteksi benar untuk 10+ kasus (termasuk rename-ekstensi ZIP-based); PDF
regression: konversi PDF desktop & web tetap hijau.

### M2 — TextExtractor + CsvExtractor (1–1.5 jam)

- Text: BOM strip, UTF-8 detect/fallback, paragraf split.
- CSV: quoted fields, header/separator/rows, baris kosong dilewati.
- Unit test: encoding, koma/kutip dalam field, CRLF, baris kosong.

**DoD M2:** unit test per kasus; file nyata `.txt`/`.csv` → md valid.

### M3 — JsonExtractor + XmlExtractor (1 jam)

- JSON: parse validasi → pretty-print → ` ```json ` code block; invalid → `ConvertError.corrupt`.
- XML: format indented → ` ```xml `.
- Unit test: nested/array; invalid input → error per-file, batch lanjut.

### M4 — HtmlExtractor (1.5–2 jam)

- Tambah dep `html` (pure Dart) — satu-satunya dep baru di Fase 1.
- DOM → blocks sesuai tabel §5.3; fallback teks bila tak ada struktur.
- Unit test: heading berlapis, list bertingkat, tabel, no-structure fallback.

### M5 — UI + integrasi (1–1.5 jam)

- Picker: `XTypeGroup` multi-extension (semua ekstensi §4.2) + label "All supported".
- `FileCard`: ikon per format (desain: picture_as_pdf / description / table / data_object / audio / folder_zip).
- Probe: PDF → pageCount (existing); non-PDF → null → progress indeterminate hingga hasil (UI sudah toleran).
- DropZone sub: "PDF & more". Drop URL → SnackBar "requires internet — not supported".
- **Branding MarkIt** (jalan paralel, §11): `strings.appTitle`/`app.dart` → `MarkIt`;
  `brand_lockup` subtitle → "Convert documents into structured Markdown"; `web/index.html`
  (title + splash), `manifest.json`, `README.md`, ZIP name → `markit-converted.zip`;
  `widget_test` expect text `MarkIt`.

### M6 — Test & verifikasi (1 jam)

- Unit `detectFormat` (10+ kasus) + tiap extractor (input sintetik inline).
- Integration: batch campur PDF+CSV+JSON+HTML → semua done, md valid, ZIP download berisi semua.
- Widget: picker multi-ext, ikon per format, probe null-safe.
- `flutter analyze` 0 · `flutter test` hijau · build Windows + web · deploy · tulis `docs/multi-format.md` (status hasil).

**DoD Fase 1:** 100% test hijau (existing + baru), analyze 0, build dua platform OK, deploy live.

---

## 7. Roadmap Fase 2 & 3 (tidak dieksekusi sekarang — referensi)

| Fase | Isi | Catatan arsitektur |
|---|---|---|
| **2** | DOCX · EPUB · XLSX | Semua ZIP+XML; DOCX memakai `w:pStyle` → heading semantik (kualitas > heuristic PDF); EPUB reuse HtmlExtractor; XLSX perlu `sharedStrings` |
| **3** | PPTX · ZIP rekursif · Image/Audio EXIF | ZIP-bomb guard (limit ukuran entry); EXIF via `image`/parser tag murni Dart |

---

## 8. Risiko & Mitigasi

| Risiko | Dampak | Mitigasi |
|---|---|---|
| Encoding text (UTF-16/BOM/ANSI) | Output mojibake | BOM strip + UTF-8 detect, fallback latin1, test encoding |
| HTML tidak well-formed | Parse gagal | `html` package tolerant; fallback satu blok teks |
| Memori: semantic extractor baca bytes penuh (file besar) | Web/desktop memori tinggi | Worker isolate untuk non-PDF di desktop; warning >100 halaman existing; Fase 3 limit entry ZIP |
| Rename ekstensi (mis. `.pdf` palsu) | Salah deteksi | Magic bytes diutamakan untuk kontainer; fallback ekstensi |
| Regression pipeline PDF | Fitur utama rusak | Integration test PDF existing sebagai safety net di tiap milestone |
| `html` dep baru | Supply chain / size | Pure Dart, size kecil; catat di `pubspec.yaml` |

---

## 9. Urutan Commit (Fase 1, saat dieksekusi)

1. `feat: input format detection + FormatExtractor interface (M1)`
2. `feat: text/csv extractors (M2)`
3. `feat: json/xml extractors (M3)`
4. `feat: html extractor (M4)`
5. `feat: multi-format UI — picker, icons, probe (M5)`
6. `test: multi-format suite + docs (M6)`

Setiap milestone di-commit terpisah (git flow: branch `feature/multi-format`, PR ke `develop`).

---

## 10. Checklist Approval

- [ ] Review arsitektur §3 & spesifikasi §4–5
- [ ] Konfirmasi urutan fase (1 → 2 → 3) & skope "tidak dikerjakan" §2.3
- [ ] Konfirmasi ekstensi picker & penanganan URL (SnackBar)
- [ ] Konfirmasi rebrand §11 (nama `markit`, tagline, scope A–D)
- [ ] **SIGN-OFF untuk mulai eksekusi Fase 1 (M1 → M6) + rebrand**

---

## 11. Rebrand `pdflow` → `MarkIt` (keputusan locked, jalan paralel)

Nama baru dipilih karena produk kini multi-format (bukan PDF-only); tagline resmi:
**"Convert documents into structured Markdown"**. Status nama: `markit` tersedia di pub.dev ✅.

### 11.1 Daftar perubahan

| Bagian | File | Perubahan |
|---|---|---|
| A. Package | `pubspec.yaml` | `name: markit` |
| A. Package | `lib/`, `test/`, `benchmark/` (~100 file) | `import 'package:pdflow/...'` → `package:markit/...` (sedot massal) |
| A. Package | `test/**` | `createTemp('pdflow_*')` → `markit_*` |
| B. Display | `lib/i18n/strings.dart`, `lib/app.dart` | `MarkIt` |
| B. Display | `lib/ui/widgets/header/brand_lockup.dart` | Subtitle → "Convert documents into structured Markdown" |
| B. Display | `lib/ui/widgets/left_panel.dart` | ZIP name → `markit-converted.zip` |
| B. Display | `test/widget_test.dart` | `find.text('MarkIt')` |
| B. Display | `web/index.html` | Title "MarkIt — Documents to Markdown", splash, CSS ids → `markit-*` |
| B. Display | `web/manifest.json` | name/short_name → MarkIt |
| B. Display | `README.md` | Judul + tagline + URL live demo |
| C. Native | `windows/CMakeLists.txt`, `linux/CMakeLists.txt` | BINARY_NAME/APPLICATION_ID → markit |
| C. Native | `macos/`, `ios/` | Grep penuh saat eksekusi (`AppInfo.xcconfig`, `pbxproj`) |
| D. Repo | GitHub | Rename repo `pdflow` → `markit` (URL lama auto-redirect 301) |
| D. Repo | `.github/workflows/deploy-web.yml` | `--base-href /markit/` |
| D. Repo | `docs/web-deploy.md`, `web-m1.md`, `benchmark.md` | URL/nama (judul; konten historis boleh dibiarkan) |
| D. Repo | Folder lokal | `D:\Projects\Flutter\pdflow` → `markit` (di akhir) |
| D. Repo | Live URL baru | `https://ezherielll.github.io/markit/` |

### 11.2 Urutan

1. Branch `feature/rename-markit` dari `develop` (git status bersih)
2. Sedot massal `pdflow` → `markit` (import, temp prefix, CMake, yml)
3. Edit manual branding display (bagian B: `MarkIt` + tagline)
4. Grep `pdflow` = 0 (kecuali docs historis) → `flutter pub get` → `analyze` 0 → `test` hijau
5. Build Windows + web `--base-href /markit/` · verifikasi splash & download
6. Commit 1 `refactor: rename package pdflow → markit` · Commit 2 `feat: rebrand to MarkIt (UI, web, native identifiers)` · Commit 3 `chore: deploy base-href /markit/ + docs`
7. Merge → push → **rename repo GitHub** → Action deploy → verifikasi URL baru 200 + redirect lama
8. Rename folder lokal + cek `git remote`

### 11.3 Risiko

| Risiko | Mitigasi |
|---|---|
| Lupa referensi di `macos/`/`ios/` | Grep penuh termasuk binary/config sebelum commit |
| `widget_test` hardcoded text | Jadi bagian sedot massal + edit manual `MarkIt` |
| URL lama 404 setelah rename repo (assets base-href `/pdflow/`) | Rename repo **hanya setelah** commit base-href baru; deploy ulang segera |
| Replace massal salah sasaran | Verifikasi diff per file; grep `pdflow` = 0
