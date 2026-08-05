# Web Deployment — GitHub Pages

## Cara deploy

1. Push ke `master` — workflow `.github/workflows/deploy-web.yml` otomatis:
   - Build `flutter build web --release --base-href /pdflow/`
   - Upload artifact → deploy ke GitHub Pages.
2. URL: `https://<user>.github.io/pdflow/` (repo `pdflow`, sub-path `/pdflow/`).

## Manual (opsional, jika workflow tidak dipakai)

```sh
flutter build web --release --base-href /pdflow/
# upload isi build/web ke branch gh-pages (atau hosting statis lain)
```

## Catatan hosting

- `--base-href /pdflow/` wajib untuk project Pages (sub-path). Untuk root domain, ganti jadi `/`.
- Flutter web default hash routing — tidak butuh SPA fallback/rewrite.
- MIME `application/wasm` disediakan otomatis oleh GitHub Pages.
- Bundle release ±47 MB (termasuk canvaskit variants); gzip di server static sangat membantu (main.dart.js ~2 MB → ~500 KB).

## Batasan web vs desktop

- Output konversi di-download (Blob), bukan ditulis ke disk.
- Drag & drop bergantung dukungan browser (fallback: tombol picker).
- File besar dibaca penuh ke memory (browser limitation).
- Konversi jalan di main isolate (inline) — UI tetap responsif antar halaman.
