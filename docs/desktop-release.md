# Desktop Release — GitHub Releases

The `.github/workflows/release-desktop.yml` workflow builds desktop artifacts
(Windows / macOS / Linux) and attaches them to a **GitHub Release (draft)**
whenever a version tag is pushed. Artifacts are generated as a portable ZIP (Windows),
a DMG (macOS, ARM64), and a tarball (Linux).

## How to Release

1. **Bump version** in `pubspec.yaml` (e.g. `1.1.0+1` → `1.2.0+2`),
   commit, and push to master.

   ```sh
   git checkout master && git pull
   # edit version in pubspec.yaml
   git commit -am "release: bump to v1.2.0"
   git push origin master
   ```

2. **Tag & push** (the workflow is triggered by `v*` tags, not branches):

   ```sh
   git tag -a v1.2.0 -m "MarkIt v1.2.0"
   git push origin v1.2.0
   ```

3. Wait for the workflow to complete in **Actions → Release Desktop**. Jobs:
   - `build-windows` → `markit-windows-x64-v1.2.0.zip`
   - `build-macos`   → `markit-macos-arm64-v1.2.0.dmg`
   - `build-linux`   → `markit-linux-x64-v1.2.0.tar.gz`
   - `release`       → creates a **Draft Release** containing all three files
     (auto-generated release notes from commits).

4. **Review and Publish** the draft release at
   [Releases](https://github.com/Ezherielll/MarkIt/releases). The
   `releases/latest` page and README badges will automatically point to the newest release.

> Tags ending in `*-web` (e.g. `v1.1.0-web`) are excluded from desktop builds — they
> are reserved for web milestones.

## Manual Trigger (Without Tags)

1. Go to **Actions → Release Desktop → Run workflow**.

### Local Windows Build (Additional Prerequisite)

`super_native_extensions` (drag & drop plugin, via cargokit) requires the
**Rust toolchain** to build native assets — CI runners already have it installed,
local machines may not.

```sh
winget install --id Rustlang.Rustup -e          # rustup + stable + MSVC target
# refresh PATH in a new shell: cargo --version
flutter clean && flutter pub get
flutter build windows --release
```

Without Rust, `flutter build windows` fails at `dart_build` /
`super_native_extensions_plugin_cargokit` ("Cargokit BuildTool failed", exit -1).

## Per-Platform Notes

| | Runner | Artifact | Notes |
|--|--------|---------|-------|
| Windows | `windows-latest` | `.zip` (`Release/` folder) | Portable; unsigned → SmartScreen "Unknown publisher". |
| macOS | `macos-14` (ARM64) | `.dmg` | **Apple Silicon** architecture. Intel is unsupported in v1. Unsigned → Gatekeeper: right-click **Open** or run `xattr -cr`. Consumes **10× billing minutes** (macOS runner). |
| Linux | `ubuntu-latest` | `.tar.gz` (`bundle` folder) | Window icon loaded from `assets/branding/markit_icon.png`. |

All artifacts are built using `flutter build --release`.

## Limitations & Roadmap

- **Signing**: Builds are currently unsigned. Windows SmartScreen & macOS Gatekeeper
  display warnings. Future improvement: Windows code-signing certificate
  (e.g., Azure Trusted Signing) and Apple notarization (requires Developer ID).
- **macOS Intel**: Add `--universal` to the macOS job if needed.
- **Linux Distribution**: AppImage/Deb via linuxdeploy — follow-up item.

## Local Build Verification (Windows)

```sh
flutter build windows --release
# test-run once: build\windows\x64\runner\Release\markit.exe
```

macOS/Linux cannot be built from Windows — verified via CI logs
and downloaded artifacts from draft releases.