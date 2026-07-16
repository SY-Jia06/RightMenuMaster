# Security and Release

## Why the Existing 1.0 Build Triggers Trust Problems

The installed development build is signed with `Apple Development`, includes debug and preview dylibs, has `get-task-allow`, does not enable Hardened Runtime, and has no stapled notarization ticket. The old README also tells users to remove quarantine attributes. These properties are valid for local development but invalid for a trustworthy public GitHub release.

The legacy Finder extension also grants temporary read/write exceptions rooted at `/`, while the product exposes scripts and destructive file actions. Version 2 removes that combination from the public surface.

## Free Unsigned Beta

The GitHub beta is ad-hoc signed so nested code and Finder-extension entitlements remain internally consistent, but it has no Developer ID identity or Apple notarization ticket. Gatekeeper therefore blocks first launch. Users must explicitly allow the app through **System Settings → Privacy & Security → Open Anyway**. The project never asks users to disable Gatekeeper or remove quarantine attributes.

The free unsigned host app is not sandboxed because ad-hoc updates cannot provide a stable sandbox identity and a Home bookmark cannot enumerate the ordinary first-level folders Finder Sync requires. The host still enforces the user's selected folder roots in application logic, excludes hidden Home roots and `Library` from Finder monitoring, performs no network requests, and exposes no arbitrary scripts. The embedded Finder extension remains sandboxed. A future Developer ID build keeps both processes sandboxed.

`scripts/package-unsigned-macos.sh` builds the Release configuration, applies an ad-hoc Hardened Runtime signature, keeps the Finder extension sandboxed, creates a DMG, and writes a SHA-256 checksum.

## Future Notarized Release Gate

A public artifact must pass every command:

```bash
codesign --verify --deep --strict --verbose=2 RightMenuMaster.app
codesign -dv --verbose=4 RightMenuMaster.app
spctl --assess --type execute --verbose=4 RightMenuMaster.app
xcrun stapler validate RightMenuMaster.app
```

Expected properties:

- `Developer ID Application` signing identity
- Hardened Runtime flag
- no `get-task-allow`
- no debug or preview dylibs
- every nested binary signed by the same team
- accepted notarization and stapled ticket

Release automation archives a Release configuration, signs nested code, creates a DMG, submits with `notarytool`, staples the accepted ticket, verifies the final DMG, generates SHA-256 checksums, and publishes immutable GitHub Release assets.

Developer ID credentials and notarization credentials live only in protected CI secrets or the developer keychain. They are never stored in the repository.

The macOS release workflow expects these GitHub Actions secrets:

- `APPLE_TEAM_ID`
- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_KEYCHAIN_PASSWORD`
- `NOTARY_API_KEY_P8_BASE64`
- `NOTARY_KEY_ID`
- `NOTARY_ISSUER_ID`

A manual workflow run produces an unpublished notarized artifact for inspection after credentials are configured. Publishing the free unsigned beta does not invoke this workflow.

## Windows Status

Windows is not a supported or released Version 2 platform. No Windows artifact or workflow is part of this release.

## Local Development

Development builds may use Apple Development signing. Public free beta artifacts are explicitly named `unsigned` and documented as unnotarized.
