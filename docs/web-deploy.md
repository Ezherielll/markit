# Web Deployment — GitHub Pages

## Deployment Guide

1. Push to `master` — the `.github/workflows/deploy-web.yml` workflow automatically:
   - Builds `flutter build web --release --base-href /MarkIt/`
   - Uploads artifact → deploys to GitHub Pages.
2. Production URL: `https://ezherielll.github.io/MarkIt/` (repository `MarkIt`, base href `/MarkIt/`).

## Manual Deployment (Optional)

```sh
flutter build web --release --base-href /MarkIt/
# upload build/web contents to gh-pages branch or static hosting
```

## Hosting Notes

- `--base-href /MarkIt/` is required for GitHub Pages project sub-paths. For root domains, set to `/`.
- Flutter web defaults to hash routing — no SPA fallback/rewrite needed.
- MIME type `application/wasm` is automatically supplied by GitHub Pages.
- Web release bundle is ~47 MB (including CanvasKit variants); server-side gzip compression reduces payloads significantly (`main.dart.js` ~2 MB → ~500 KB).

## Web vs Desktop Differences

- Conversion output is downloaded via browser Blob, not saved directly to disk.
- Drag & drop relies on browser event support (fallback: "Choose Files" button).
- Large files are loaded into memory (`Uint8List` in `PdfInput.bytes`).
- Conversion runs inline on the main isolate while yielding frames to maintain UI responsiveness.
