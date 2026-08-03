# PRD — PDF → Markdown Converter (Flutter Desktop)

| Field | Value |
|---|---|
| Project codename | `pdflow` |
| Status | Draft v0.1 — untuk validasi & acuan development |
| Platform | Flutter desktop: Windows 10/11 (primary), macOS 12+, Linux |
| Scope PRD | MVP (weekend) + roadmap v1/v2 |
| Prinsip utama | **Performa dulu** → **100% lokal** → **content fidelity, bukan visual fidelity** |

---

## 1. Overview & Problem Statement

**Masalah:** Dokumen PDF besar (buku 500–800 halaman, laporan, paper) sulit dibaca ulang, diedit, di-index, dan dipakai sebagai input AI (RAG/LLM). Format PDF dirancang untuk dirender, bukan untuk diekstrak. Alat konversi yang ada saat ini mayoritas:

- **Berat & kompleks** (Marker, MinerU, Docling) — butuh Python env, model ML untuk layout detection, resource besar;
- **Bergantung cloud/API** — masalah privasi dan tidak bisa offline;
- **Kualitas markdown buruk** — heading tidak terstruktur, noise nomor halaman, paragraf terpotong, sehingga hasilnya jelek untuk chunking/RAG.

**Solusi:** Aplikasi desktop ringan berbasis Flutter yang mengonversi PDF teks-digital menjadi Markdown terstruktur (heading/paragraf/list) dengan cepat via pipeline **murni heuristik** (posisi, ukuran font, bounding box) — tanpa model ML, tanpa cloud. Divalidasi lewat prototype: ekstraksi ±42 ms/halaman single-thread → buku 500–800 halaman bisa selesai ±20–35 detik, cukup cepat untuk MVP tanpa paralelisasi.

**Kenapa penting:** (a) kebutuhan pribadi konversi dokumen; (b) use case AI/RAG menuntut markdown yang *machine-readable baik* — struktur heading akurat untuk chunking, paragraf koheren, minim noise — bukan sekadar "jadi .md".

---

## 2. Goals & Non-Goals

### Goals
| ID | Goal | Terukur via |
|---|---|---|
| G1 | Konversi cepat PDF besar (ratusan halaman) | Metrik throughput §4 |
| G2 | 100% lokal & offline — nol panggilan jaringan untuk konversi | Verifikasi di kode (tidak ada http client pada pipeline) |
| G3 | Memory footprint rendah pada dokumen besar | Streaming write per halaman; metrik memori §4 |
| G4 | Markdown terstruktur dengan **content fidelity tinggi** (urutan benar, isi lengkap, heading/paragraf/list diklasifikasi benar) | Evaluasi golden corpus §4 |
| G5 | Hasil cocok untuk input AI/RAG: minim noise (header/footer/pagination), heading akurat untuk chunking | Akurasi struktur + noise rate §4 |
| G6 | UX desktop yang layak: pilih file, progress per halaman, preview, save | Kriteria penerimaan FR |
| G7 | Transparansi akurasi: user diperingatkan saat heuristik kemungkinan gagal (mis. multi-kolom) | FR-24 |

### Non-Goals (eksplisit TIDAK dikerjakan)
| ID | Non-Goal | Alasan |
|---|---|---|
| NG1 | **OCR untuk PDF hasil scan** | Bottleneck performa; di luar scope MVP (fase jauh ke depan) |
| NG2 | **Visual fidelity** — layout multi-kolom rapi, posisi absolut, tabel kompleks (merged cells), font/warna custom, elemen dekoratif | Keterbatasan format Markdown, bukan bug; target adalah content fidelity |
| NG3 | Semua ketergantungan cloud/API eksternal | Privasi + offline |
| NG4 | Target mobile & web | Scope desktop |
| NG5 | Deteksi multi-kolom, tabel kompleks, ekstraksi gambar di MVP | Fase berikutnya (lihat §9) |
| NG6 | Pembuatan/penyuntingan PDF | Beda produk |
| NG7 | Konversi batch multi-file di MVP | V2 (opsional) |

**Akurasi realistis (ekspektasi, bukan bug):** buku satu kolom 85–95% · dokumen tabel sederhana 70–85% · paper multi-kolom 50–70% (tanpa deteksi kolom) · scan 0% (tanpa OCR) · majalah/brosur 30–50%. Benchmark tools lain (Marker/MinerU/Docling/pymupdf4llm) umumnya 80–95% tapi pakai teknik lebih canggih — ekspektasi ini yang jadi kalibrasi.

---

## 3. Target Users & Use Cases

**Personas**
1. **Solo developer / hobbyist** — convert buku teknis untuk dibaca/di-index. Butuh: cepat, gratis, tanpa setup berat.
2. **Knowledge worker** — arsip dokumen pribadi menjadi markdown yang bisa dicari/diedit.
3. **AI/LLM hobbyist & practitioner** — mempersiapkan korpus (buku, paper, laporan) untuk RAG/embedding/fine-tuning. **Driver kualitas utama**: struktur yang chunkable, minim noise.

**Use cases**
| UC | Deskripsi | Prioritas kualitas |
|---|---|---|
| UC1 | Convert buku/dokumen PDF pribadi → .md untuk dibaca/diedit/di-index | Sedang |
| UC2 | Prep dokumen untuk AI (RAG/upload ke LLM/fine-tuning): heading akurat untuk chunking, paragraf koheren, bebas header/footer berulang & nomor halaman | **Tinggi** — penentu urutan prioritas fitur |
| UC3 | Konversi paper/laporan berkala jadi korpus lokal | Sedang–tinggi (tergantung multi-kolom) |

---

## 4. Success Metrics

### Kuantitatif (reference machine: i5/i7-class, RAM 16 GB, NVMe SSD, Windows 11 — harus dicatat saat benchmark)
| Metrik | Target MVP | Target v1 |
|---|---|---|
| Throughput ekstraksi | ≥ 20 halaman/detik rata-rata (≤ 50 ms/halaman p95) pada dokumen teks-berat satu kolom | Tetap ≥ 20 hal/s dengan filter header/footer & multi-kolom aktif |
| Total waktu buku 500 hal | ≤ 35 s | ≤ 40 s (fitur baru, tetap dalam batas) |
| Total waktu buku 800 hal | ≤ 55 s | ≤ 65 s |
| Peak memory buku 800 hal | ≤ 400 MB (target ≤ 250 MB) | ≤ 500 MB (dengan ekstraksi gambar) |
| Conversion success rate (non-corrupt) | ≥ 98% korpus uji tanpa crash; 100% kegagalan = error terlihat user, bukan hang | Sama |
| Paragraph-level fidelity (F1 vs golden) — satu kolom | ≥ 0.90 | ≥ 0.92 |
| Akurasi level heading (dokumen hierarki jelas) | ≥ 85% tepat level | ≥ 90% (multi-tier) |
| Recall deteksi list (bullet) | ≥ 80% | ≥ 85% |
| Noise header/footer (per 100 hal) | Baseline diukur | ≤ 1 (target 0) |

### Kualitatif
- Tidak ada hang/membeku pada file raksasa; progress selalu terlihat.
- User bisa menebak hasil dengan percaya diri (preview + warning bila struktur mencurigakan).
- Konversi dapat dijalankan 100% offline tanpa permission jaringan.

---

## 5. Functional Requirements

### 5.1 MVP — Fase Weekend (acuan development, lengkap dengan perilaku & kriteria penerimaan)

| ID | Requirement | Detail perilaku | Acceptance criteria |
|---|---|---|---|
| FR-01 | Pilih file PDF | Dialog file picker (native). Satu file per sesi. Tampilkan nama file, ukuran, jumlah halaman (dari metadata pdfrx) setelah dipilih | File terpilih → jumlah halaman terbaca < 2 s; PDF corrupt/encrypted ditolak dengan pesan jelas (lihat FR-10) |
| FR-02 | Ekstraksi fragment per halaman | Pipeline stage 1: per halaman ambil fragment (teks + x0,y0,x1,y1,font size,run). Hasil per halaman **tidak di-accumulate** — diproses lalu dibebaskan | Konsumsi memori stabil per halaman (tidak naik linier dengan total halaman) |
| FR-03 | Grouping baris | Stage 2: fragment dikelompokkan ke baris via clustering y-coordinate (toleransi jarak vertikal). Baris diurutkan left-to-right, top-to-bottom (asumsi satu kolom) | Akurasi grouping ≥ 95% pada korpus satu kolom (uji golden) |
| FR-04 | Penggabungan paragraf | Stage 3: baris jadi paragraf jika gap vertikal antar-baris melebihi threshold statistik (median gap × faktor), atau indent baris pertama terdeteksi | Paragraf F1 ≥ 0.90 pada korpus satu kolom |
| FR-05 | Klasifikasi heading (2-level) | Stage 4: hitung tinggi baris seluruh dokumen → modus = body text; baris di atas body (×faktor, mis. ≥1.2×) = heading. Level: heading vs body (2-tier sederhana, level dalam di v1) | ≥ 85% heading terdeteksi benar level-nya pada dokumen hierarki jelas |
| FR-06 | Deteksi list sederhana | Baris paragraf pertama diawali `•`/`-`/`*` (dan varian `o`/`▪`) → output sebagai `- item`; indent pendukung opsional | Recall ≥ 80% pada korpus berlist |
| FR-07 | Output Markdown streaming | Stage 5: hasil ditulis per halaman ke file via buffered writer (flush tiap halaman/64 KB). Konvensi: `#` heading, `-` list, paragraf dipisah baris kosong | File valid markdown; throughput write tidak menambah > 10% total waktu |
| FR-08 | UI progress & statistik | Progress bar per halaman (x/y), halaman/s, waktu berjalan (elapsed), total estimasi; setelah selesai: total waktu & lokasi file | UI update tiap ≤ 500 ms; tidak jank pada file besar |
| FR-09 | Preview hasil | Setelah konversi, tampilkan preview markdown awal (render mentah + sekilas struktur: jumlah heading, paragraf, list) | Preview muncul < 1 s setelah selesai; bisa dibuka file aslinya dari tombol |
| FR-10 | Error handling dasar | (a) Corrupt/unreadable → dialog error + log, tidak crash; (b) encrypted/protected → pesan "PDF dipassword — tidak didukung" + log; (c) sebagian halaman gagal parse → lanjutkan + catat halaman gagal, tampilkan summary; (d) tidak ada teks terdeteksi (indikasi scan) → warning eksplisit "Dokumen tampaknya hasil scan — tanpa OCR, hasil akan kosong" | 100% skenario di atas menghasilkan feedback user, bukan crash/hang |
| FR-11 | Cancel | Tombol batal saat konversi berjalan; hentikan pipeline secepatnya; **file parsial dihapus** (keputusan D7) | Batal < 1 s; file parsial dihapus dan tidak tertinggal |
| FR-12 | Simpan output | Dialog save: default `nama_pdf.md` di folder PDF asal; konfirmasi overwrite; encoding **UTF-8 tanpa BOM**, line ending `\n` (keputusan D8) | File tersimpan konsisten dibuka di editor manapun |

### 5.2 Fase Berikutnya (prioritas terurut — lihat §9)

| ID | Fitur | Perilaku yang diharapkan |
|---|---|---|
| FR-20 | Filter header/footer berulang | Kumpulkan kandidat baris di margin (zona atas/bawah, mis. 8–12% halaman) yang identik/bervariasi hanya di nomor halaman pada ≥ 70% halaman → buang dari output. Nomor halaman: pola angka murni di posisi konsisten. Tidak membuang konten sah yang kebetulan mirip (uji dengan buku bab berjudul sama) |
| FR-21 | Heading multi-tier (H1–H3) | Histogram tinggi baris → deteksi 2–3 bucket di atas body (relatif terhadap body median): H1/H2/H3. Koefisien dapat di-override user di advanced settings (keputusan D9) |
| FR-22 | Deteksi multi-kolom | Sebelum grouping baris: cluster fragment berdasarkan x-position → deteksi N kolom (gap x signifikan konsisten antar baris). Reading order: kolom-per-kolom (kiri→kanan, lalu atas→bawah). Jika terdeteksi tapi fitur nonaktif/ambigu → warning (FR-24) |
| FR-23 | Deteksi tabel sederhana | Identifikasi fragment membentuk grid (≥2 baris & kolom dengan koordinat sejajar) → konversi ke sintaks tabel markdown (header + `---` separator). Hanya tabel grid sederhana; merged cells → fallback teks polos + warning |
| FR-24 | Quality warnings & confidence | Deteksi otomatis: multi-kolom terdeteksi, gambar dominan, halaman tanpa teks, proporsi teks "aneh" (font tak dikenal). Output: (a) dialog warning pra-save, (b) summary di UI. Skor kualitas sederhana (0–100) di v1 |
| FR-25 | Ekstraksi gambar | Save gambar per halaman sebagai file (`_images/pdflow_0001_3.png`) + sisipkan `![alt](path)` di posisi bounding box. Opsi include/exclude. Alokasi memori: tulis langsung ke disk, jangan simpan semua di memori |
| FR-26 | Split per bab (opsional) | Konfigurasi: satu file vs split per H1. Filename `judul_01.md`; index `SUMMARY.md`. **Default: satu file** (keputusan D1) |
| FR-27 | Front matter opsional | Opsional: metadata YAML (title, author, source file, tanggal) di header output — berguna untuk pelacakan sumber di RAG |

---

## 6. Non-Functional Requirements

| Kategori | Requirement |
|---|---|
| **Performa** | Ekstraksi ≤ 50 ms/halaman p95; total buku 500 hal ≤ 35 s, 800 hal ≤ 55 s (reference machine §4). Write streaming tidak menambah > 10% total. Startup app < 2 s |
| **Memory** | Peak ≤ 400 MB untuk 800 halaman (MVP); tidak menyimpan fragment > 1 halaman di memori. Cancellation & error path tidak bocor memori (uji dengan 2× konversi berturut) |
| **Kompatibilitas** | Windows 10/11 x64 (primary, test wajib), macOS 12+ (test jika tersedia), Linux (best effort, AppImage). PDFium dibundle benar per platform oleh pdfrx |
| **Offline/lokal** | Nol panggilan jaringan pada alur konversi (verifikasi: grep `http`/`socket` pada dependency pipeline di CI check); tidak ada permission jaringan khusus |
| **Keandalan** | Tidak crash pada input apapun (fuzzing ringan korpus); error selalu user-visible; partial failure = lanjut + laporan |
| **Encoding** | Input PDF: handle Unicode, CJK (uji korpus minimal 1 file non-Latin); output UTF-8 tanpa BOM |
| **Observability** | Log file lokal (opsional, verbose mode) untuk diagnosa dokumen bermasalah |

---

## 7. Technical Architecture Summary

```
PDF ──► [Stage 1] Ekstraksi fragment (pdfrx/PDFium)
          fragment = {text, x0, y0, x1, y1, fontSize}
   ──► [Stage 2] Grouping → baris (clustering y + ordering x)
   ──► [Stage 3] Baris → paragraf (gap vertikal berbasis statistik)
   ──► [Stage 4] Klasifikasi struktur (heading/list)
          └─ histogram tinggi baris seluruh dokumen → body baseline
   ──► [Stage 5] Generate Markdown → buffered writer streaming/halaman
```

**Keputusan tervalidasi:**
- **`pdfrx`** (binding PDFium) untuk ekstraksi — dipilih vs syncfusion (lisensi) dan FFI MuPDF manual (kompleksitas).
- **Single-thread + streaming write** cukup untuk MVP: ±42 ms/halaman → buku 500–800 hal ±20–35 s. Isolate pool = rencana cadangan (bukan default).
- **Klasifikasi berbasis statistik dokumen** (body font = nilai paling sering), bukan threshold hardcoded.

**Catatan arsitektur penting yang perlu diklarifikasi saat implementasi:**
1. **Konflik streaming vs statistik global**: klasifikasi heading butuh histogram *seluruh dokumen*, tapi write bersifat streaming per halaman. Opsi: (a) **two-pass** — pass 1 baca cepat teks+font size saja (tanpa layout, jauh lebih murah) untuk histogram, pass 2 ekstraksi penuh + klasifikasi + write; (b) stats inkremental (bias pada halaman awal, perlu diuji). **Keputusan D5 — rekomendasi: two-pass**, dengan catatan tetap dalam budget waktu.
2. **Isolate**: jalankan pipeline di 1 background isolate agar UI tetap responsif; komunikasi via port (progress, per halaman). Ini bukan paralelisasi — hanya pemisahan UI.
3. **Isolate pool (cadangan)**: tiap worker buka handle PDF read-only sendiri, hasil ke file sementara terpisah, digabung berurutan → menghindari reordering out-of-order.
4. Satuan tinggi baris: fontSize PDFium kadang tidak = line height aktual — pakai tinggi bounding box baris sebagai fallback, dan kalibrasi di korpus.

**Dependensi:** flutter + pdfrx + dart:io (file streaming) + file picker. Tidak ada dependency ML/network. Tooling dev: lints default Flutter, unit test murni Dart, integrasi test di korpus.

---

## 8. Known Limitations & Risks

### Keterbatasan format (bukan bug)
- Markdown **tidak bisa** merepresentasikan: layout multi-kolom presisi, posisi absolut, tabel kompleks (merged cells/colspan), font/warna custom, elemen dekoratif. Target = content fidelity.

### Variasi akurasi per tipe dokumen
| Tipe | Akurasi realistis | Catatan |
|---|---|---|
| Buku teks satu kolom, heading jelas | 85–95% | Kasus terbaik |
| Dokumen tabel sederhana | 70–85% | Tabel = baris menyatu; perbaiki di v2 |
| Paper akademik multi-kolom | 50–70% | Perlu deteksi kolom (FR-22) |
| PDF hasil scan | 0% (tanpa OCR) | Di luar scope |
| Majalah/brosur layout kompleks | 30–50% | Di luar target utama |

### Risiko teknis
| Risiko | Dampak | Mitigasi |
|---|---|---|
| Long-tail PDF quirks (encoding rusak, ToUnicode hilang, font CJK, PDF v1.x tua) | Halaman kehilangan teks / char rusak | Korpus uji beragam (§11), log + partial-failure handling (FR-10) |
| Ketergantungan pdfrx (maturity, packaging PDFium per platform) | Build/CI masalah, bug di platform tertentu | Pin versi, test matrix 3 platform (Windows wajib), punya exit plan: FFI MuPDF bila macet |
| Heading misklasifikasi pada dokumen tidak beraturan | Struktur MD jelek → RAG chunking salah | Stats-based (bukan hardcode) + warning (FR-24) + override settings |
| Scope creep weekend | MVP molor | Definisi selesai ketat §11; fitur non-MVP masuk backlog §9 |
| Benchmark korpus bias (file uji kecil) | Target performa keliru | Validasi wajib di file besar & kompleks (banyak gambar/tabel) di akhir MVP — **decision gate** isolate pool |

---

## 9. Prioritization — Fitur "Belum Diimplementasi"

Dibobot untuk **AI/RAG use case (kualitas struktur) + prioritas performa + lokal-first**. Effort estimasi pengembang tunggal (akhir pekan).

| Rank | Fitur | Dampak (AI/RAG + akurasi) | Effort | Fase | Alasan |
|---|---|---|---|---|---|
| **1** | Filter header/footer berulang | **Tinggi** — noise (nomor halaman, judul bab berulang) mengotori embedding & retrieval per chunk | Rendah–sedang (bandingkan koordinat+teks antar halaman) | **v1** | ROI terbaik: murah, langsung menaikkan kualitas korpus AI |
| **2** | Heading multi-tier presisi (H1–H3) | **Sedang–tinggi** — chunking RAG butuh hierarki; naikkan akurasi 85→90% | Rendah (ekstensi histogram yang sudah ada) | **v1** | Membangun di atas stage 4 yang sudah tervalidasi |
| **3** | Deteksi multi-kolom | **Tinggi** — paper akademik (target penting AI) sekarang 50–70%; kolom benar → +20–30 poin | Sedang–tinggi (x-clustering + reading order, perlu test ketat) | **v1 akhir/v2 awal** | Dampak besar tapi effort lebih mahal & risiko regresi reading order; **dahulukan warning** (FR-24) dulu sebelum implementasi penuh |
| **4** | Quality warnings & confidence | **Sedang** — trust & transparansi; arahkan user keluar dari dokumen yang hasilnya akan jelek | Rendah (heuristics sederhana) | **v1** | Murah, sinergi dengan #3 (warning multi-kolom) |
| **5** | Ekstraksi gambar | Sedang — hanya berguna untuk buku berilustrasi; kecil efek ke RAG teks | Sedang (API pdfrx + tulis ke disk + path relatif) | **v2** | Use case terbatas |
| **6** | Deteksi tabel | Rendah–sedang — tabel sederhana saja; grid heuristic rapuh; RAG biasanya lebih butuh teks polos yang benar urutannya | **Tinggi** (grid detection + fallback + testing) | **v2** | Effort tinggi vs dampak terbatas; implementasi di akhir |
| **7** | Isolate pool paralel | Kondisional — MVP kemungkinan cukup single-thread | Tinggi (worker lifecycle, temp files, ordered merge) | **v2, hanya jika benchmark gagal** | Jangan dibangun prematur; keputusan ditunda ke decision gate MVP |
| **8** | OCR | Sangat tinggi untuk scan, tapi eksplisit non-goal MVP | Sangat tinggi | **v3+ (jauh)** | Bertentangan dengan prioritas performa; tetap dicatat |

**Keputusan yang disarankan:** v1 = #1, #2, #4 (+ warning #3 tanpa implementasi kolom penuh). v2 = #3, #5, #6. #7 kondisional. #8 ditunda.

---

## 10. Keputusan & Open Questions

Semua pertanyaan terbuka pada saat drafting sudah **diputuskan** memakai rekomendasi. Tercatat di sini agar tidak di-rehash.

| ID | Topik | **Keputusan (locked)** |
|---|---|---|
| D1 | Split output per bab vs satu file | **Satu file** per PDF. Split per bab (FR-26) = opsi v2, default tetap satu file |
| D2 | PDF corrupt/encrypted total | Error dialog jelas + log (FR-10); encrypted tidak didukung MVP |
| D3 | Preview side-by-side (PDF vs MD) sebelum save | **Tidak di MVP.** Konversi langsung ke file + preview setelahnya (FR-09). Side-by-side = v2 bila perlu |
| D4 | Definisi "selesai" & quality score/warning | Selesai = convert + save sukses + preview. Warning otomatis (bukan skor penuh) di v1 (FR-24); skor 0–100 di v1 akhir bila waktu memungkinkan |
| D5 | Stats vs streaming (two-pass) | **Two-pass**: pass 1 histogram cepat → pass 2 ekstraksi + klasifikasi + write. Dikonfirmasi saat implementasi M0; fallback stats inkremental jika overhead terbukti signifikan |
| D6 | Referensi mesin & korpus benchmark | Reference machine dicatat di repo (i5/i7-class, 16 GB, NVMe, Win 11); korpus 8–15 PDF domain publik (Project Gutenberg, arXiv, laporan pemerintah) + golden manual |
| D7 | Overwrite & file parsial saat cancel | Konfirmasi overwrite; cancel → **file parsial dihapus** |
| D8 | Encoding/line ending | UTF-8 tanpa BOM, line ending `\n` |
| D9 | Threshold heading dikonfigurasi user | Advanced settings di v1 (override koefisien); default stats-based |
| D10 | Bahasa UI | **Inggris primary**; struktur kode siap i18n (string terpusat), lokalisasi ID ditunda |

**Tetap dijadwalkan ulang di fase berikutnya (bukan open question):** batch multi-file (v2), side-by-side preview (v2, conditional), front matter (v2 opsional), OCR (v3+, jauh).

---

## 11. Milestone / Rollout Plan (solo developer, weekend-based)

### M0 — MVP "Weekend" (target: 1 akhir pekan intensif + 1–2 sore)
**Scope (freeze):** FR-01 s/d FR-12 saja. **Tidak ada** fitur §9.
- Selesaikan pipeline (stages 1–5) + UI (pick, progress, preview, save) + error handling (FR-10) + cancel (FR-11).
- **Bangun korpus benchmark awal (8–10 file)**: buku satu kolom ×3, buku dengan heading berlapis ×2, dokumen tabel sederhana ×2, dokumen non-Latin ×1, PDF scan ×1 (uji warning), PDF corrupt ×1 (uji error). Golden output manual untuk evaluasi akurasi.
- **Decision gate performa (exit criteria wajib):** jalankan di file besar kompleks (gambar/tabel). Jika buku 800 hal ≤ 55 s & memori ≤ 400 MB → **isolate pool dibatalkan/tunda (keputusan: SKIP)**; jika tidak → tulis backlog v2 #7.
- **Exit criteria MVP:** semua acceptance FR-01..12 lulus; benchmark tercatat di `docs/benchmark.md`; tidak ada hang; akurasi single-col ≥ 0.90 F1 paragraf.

### M1 — v1 "Kualitas AI" (target: 1–2 akhir pekan)
- #1 Filter header/footer (FR-20) · #2 Heading multi-tier (FR-21) · #4 Quality warnings (FR-24) + advanced settings (D9).
- Perluas korpus ke 12–15 file (termasuk 2 paper 2-kolom untuk mengukur baseline warning multi-kolom).
- **Exit criteria:** noise header/footer ≤ 1/100 halaman; akurasi heading ≥ 90%; warning multi-kolom benar ≥ 90% pada korpus; throughput ≥ 20 hal/s.

### M2 — v2 "Konten lengkap" (target: 2–4 akhir pekan, fleksibel)
- #3 Multi-kolom penuh (FR-22) · #5 Ekstraksi gambar (FR-25) · #6 Tabel sederhana (FR-23) · opsional FR-26 split bab, FR-27 front matter, batch mode.
- **Exit criteria:** paper 2-kolom ≥ 80% akurasi (dari baseline 50–70%); tabel sederhana terkonversi ≥ 70%; tidak ada regresi metrik M0/M1.

### M3 — Jauh ke depan (tidak dijadwalkan)
- OCR (scan PDF), fitur RAG-advanced (front matter otomatis, marker chunking semantik), isolate pool bila dibutuhkan, CI publish installer (Windows/macOS/Linux).

**Catatan backlog:** semua fitur non-MVP tersimpan sebagai FR-20..27 dengan estimasi effort agar bisa direplan bila prioritas berubah.
