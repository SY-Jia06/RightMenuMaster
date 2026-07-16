# Security and Release

## Why the Existing 1.0 Build Triggers Trust Problems

The installed development build is signed with `Apple Development`, includes debug and preview dylibs, has `get-task-allow`, does not enable Hardened Runtime, and has no stapled notarization ticket. The old README also tells users to remove quarantine attributes. These properties are valid for local development but invalid for a trustworthy public GitHub release.

The legacy Finder extension also grants temporary read/write exceptions rooted at `/`, while the product exposes scripts and destructive file actions. Version 2 removes that combination from the public surface.

## macOS Release Gate

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

A manual workflow run produces an unpublished artifact for inspection. A signed `v*` tag also creates or updates the matching GitHub Release.

## Windows Status

Windows is not a supported or released Version 2 platform. No Windows artifact or workflow is part of this release.

## Local Development

Development builds may use Apple Development or ad-hoc signing. Development scripts must label these artifacts as non-distributable and must not publish them to Releases.
