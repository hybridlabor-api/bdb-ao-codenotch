# Releasing BDB AO Codenotch

Source stays in the private repo `hybridlabor-api/bdb-ao-codenotch`. Binaries are published to the public, releases-only repo `hybridlabor-api/bdb-ao-codenotch-releases`.

## Cut a release

1. Set `MARKETING_VERSION` in `project.yml` to the new version and merge to `main`.
2. Create a tag `v<version>` (for example `v1.21.0`) on that commit and push the tag to `origin`.
3. `.github/workflows/bdb-build.yml` runs the build and test jobs, then the `release` job (tag pushes of this repo only, never pull requests). It:
   - builds the app and dmg with `make bdb-build` (SwiftPM, ad-hoc signed),
   - names it `BDB-AO-Codenotch-<version>.dmg` (version = tag without `v`), runs `hdiutil verify`, writes `BDB-AO-Codenotch-<version>.dmg.sha256` (`shasum -a 256`),
   - creates a GitHub release in the releases repo with both files. The notes contain only the version and the SHA-256, no source.

A warning is logged if the tag differs from `MARKETING_VERSION` (the app would report the other version).

## Required setup (one time, by the repo owner)

- Create the **public** repo `hybridlabor-api/bdb-ao-codenotch-releases` with at least one commit on its default branch (for example a README), so `gh release create` can create the tag.
- Create a fine-grained personal access token with **Contents: Read and write** on **only** `hybridlabor-api/bdb-ao-codenotch-releases`.
- Store it as the repository secret **`RELEASES_REPO_TOKEN`** in `hybridlabor-api/bdb-ao-codenotch`. The workflow keeps `permissions: contents: read`; the token is used only by the publish step.

## Download

Users download the dmg from the Releases page of `hybridlabor-api/bdb-ao-codenotch-releases`. Check it against the `.sha256` asset: `shasum -a 256 -c BDB-AO-Codenotch-<version>.dmg.sha256`.

## Signing status

Until Apple Developer ID certificates exist, the app is ad-hoc signed and not notarised, so Gatekeeper blocks the first launch. After copying the app to `/Applications`:

```
xattr -dr com.apple.quarantine "/Applications/BDB AO Codenotch.app"
```

The workflow has a marked, disabled placeholder (to be guarded by an `APPLE_CERT` secret) where signing and notarisation will go. It is not implemented yet.
