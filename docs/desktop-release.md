# Rilis Desktop — GitHub Releases

Workflow `.github/workflows/release-desktop.yml` membangun build desktop
(Windows / macOS / Linux) dan menempelkannya ke **GitHub Release (draft)**
setiap tag versi di-push. Artefak berupa ZIP portabel (Windows), DMG
(macOS, ARM64), dan tarball (Linux).

## Cara merilis

1. **Bump versi** di `pubspec.yaml` (mis. `1.1.0+1` → `1.2.0+2`),
   commit, dan push ke master.

   ```sh
   git checkout master && git pull
   # edit version di pubspec.yaml
   git commit -am "release: bump to v1.2.0"
   git push origin master
   ```

2. **Tag & push** (workflow hanya terpicu oleh tag `v*`, bukan branch):

   ```sh
   git tag -a v1.2.0 -m "MarkIt v1.2.0"
   git push origin v1.2.0
   ```

3. Tunggu workflow selesai di **Actions → Release Desktop**. Job:
   - `build-windows` → `markit-windows-x64-v1.2.0.zip`
   - `build-macos`   → `markit-macos-arm64-v1.2.0.dmg`
   - `build-linux`   → `markit-linux-x64-v1.2.0.tar.gz`
   - `release`       → membuat **Draft Release** berisi ketiga file
     (release notes otomatis dari commits).

4. **Review lalu Publish** draft release di
   [Releases](https://github.com/Ezherielll/markit/releases). Halaman
   `releases/latest` dan badge README otomatis mengikuti release terbaru.

> Tag `*-web` (mis. `v1.1.0-web`) dikecualikan dari build desktop — itu
> tag milik milestone web.

## Build manual (tanpa tag)

1. **Actions → Release Desktop → Run workflow** (panel can run by sending the
   button "Run workflow" di UI GitHub).

## Catatan per platform

| | Runner | Artefak | Catatan |
|--|--------|---------|---------|
| Windows | `windows-latest` | `.zip` (folder `Release/`) | Portable; unsigned → SmartScreen "Unknown publisher". |
| macOS | `macos-14` (ARM64) | `.dmg` | Arsitektur **Apple Silicon**. Intel belum didukung (v1). Unsigned → Gatekeeper: kanan-klik **Open** atau `xattr -cr`. Membakar **10× billing minutes** (macOS runner). |
| Linux | `ubuntu-latest` | `.tar.gz` (folder `bundle`) | Ikon jendela dimuat dari `assets/branding/markit_icon.png`. |

Semua artefak dibangun dengan `flutter build --release`.

## Batasan & roadmap

- **Signing**: build kini unsigned. Windows SmartScreen & macOS Gatekeeper
  memberi peringatan. Perbaikan masa depan: sertifikat code-signing Windows
  (mis. Azure Trusted Signing) dan Apple notarization (butuh Developer ID —
  biaya tahunan).
- **macOS Intel**: tambah `--universal` di job macOS bila perlu.
- **Linux distribusi**: AppImage/Deb via linuxdeploy — follow-up.

## Verifikasi build lokal (Windows)

```sh
flutter build windows --release
# jalankan sekali: build\windows\x64\runner\Release\markit.exe
```

macOS/Linux tidak dapat dibangun dari Windows — diverifikasi lewat CI logs
dan artefak yang diunduh dari draft release.