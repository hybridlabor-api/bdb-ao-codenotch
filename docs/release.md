# Releasing BDB AO Codenotch

Source and binaries live in the public repo `hybridlabor-api/bdb-ao-codenotch`. Releases are published on its own Releases page.

## Cut a release

1. Set `MARKETING_VERSION` in `project.yml` to the new version and merge to `main`.
2. Create a tag `v<version>` (for example `v1.21.0`) on that commit and push the tag to `origin`.
3. `.github/workflows/bdb-build.yml` runs the build and test jobs, then the `release` job (tag pushes of this repo only, never pull requests). It:
   - builds the app and dmg with `make bdb-build` (SwiftPM, ad-hoc signed),
   - names it `BDB-AO-Codenotch-<version>.dmg` (version = tag without `v`), runs `hdiutil verify`, writes `BDB-AO-Codenotch-<version>.dmg.sha256` (`shasum -a 256`),
   - creates the GitHub release in this repo with both files. The notes contain only the version and the SHA-256, no source.

A warning is logged if the tag differs from `MARKETING_VERSION` (the app would report the other version).

### Windows installer

The same tag also ships the Windows installer into the same release:

- `windows-installer` (reusable `bdb-windows-installer.yml`, runs in parallel to the macOS jobs) builds the hook, then the NSIS installer with `npx @tauri-apps/cli@2.11.4 build --config tauri.bundle.conf.json`, and smoke-tests it: silent install (`/S`), `codenotch.exe doctor`, silent uninstall.
- `windows-release` `needs` the dmg `release` job, which creates the GitHub release. It renames the installer to `Codenotch-Setup-<version>.exe` (version = tag without `v`), writes `Codenotch-Setup-<version>.exe.sha256` (`sha256sum`) and runs `gh release upload --clobber` on the existing release. Because it needs the dmg job there is no create race; a failed macOS build means no Windows asset either.
- A warning is logged if the tag differs from `version` in `windows/codenotch/tauri.conf.json` (the Windows app's version source, also in `windows/codenotch/Cargo.toml`; keep both in step with `MARKETING_VERSION`).
- Uses the default `GITHUB_TOKEN`; tag pushes of this repo only. Workflow-level `permissions: contents: read`, `contents: write` only on the two publishing jobs.

Assets per release: `BDB-AO-Codenotch-<version>.dmg`, `.dmg.sha256`, `Codenotch-Setup-<version>.exe`, `.exe.sha256`.

`bdb-windows.yml` builds and smoke-tests the installer on pull requests and `main` touching `windows/**`, and on `workflow_dispatch`, without any upload, so it is proven before the first tag.

### Windows facts for the AOS installer

From `tauri.conf.json` and Tauri's stock NSIS template (no custom template, default per-user install):

- Product name `Codenotch`, identifier `com.immidi.codenotch`, version from `windows/codenotch/tauri.conf.json`.
- Install dir `%LOCALAPPDATA%\Codenotch` containing `codenotch.exe`, `codenotch-hook.exe`, `uninstall.exe`.
- Uninstall key `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\Codenotch`; `DisplayVersion` is the installed version, `UninstallString` points at `uninstall.exe`.
- Silent install `Codenotch-Setup-<version>.exe /S`, silent uninstall `uninstall.exe /S`. Both are per user and need no administrator rights.

## Setup

- Optional: `TAURI_SIGNING_PRIVATE_KEY` (and `_PASSWORD`) switch on updater artifacts for the Windows build, exactly as upstream. Without them the installer is still built. No update feed is published: upstream's updater endpoint and public key are placeholders in `tauri.conf.json`.

## Download

Users download the dmg or `Codenotch-Setup-<version>.exe` from the Releases page of `hybridlabor-api/bdb-ao-codenotch`. Check it against the `.sha256` asset: `shasum -a 256 -c BDB-AO-Codenotch-<version>.dmg.sha256` (macOS) or `sha256sum -c Codenotch-Setup-<version>.exe.sha256` (Linux) or `Get-FileHash` (Windows).

## Signing status

Until Apple Developer ID certificates exist, the app is ad-hoc signed and not notarised, so Gatekeeper blocks the first launch. After copying the app to `/Applications`:

```
xattr -dr com.apple.quarantine "/Applications/BDB AO Codenotch.app"
```

The workflow has a marked, disabled placeholder (to be guarded by an `APPLE_CERT` secret) where signing and notarisation will go. It is not implemented yet.

Windows installers are unsigned (no Authenticode certificate). On first run SmartScreen shows "Windows protected your PC": choose **More info**, then **Run anyway**. The installer installs for the current user only, without administrator rights; a silent install by AOS (`/S`) behaves the same.
