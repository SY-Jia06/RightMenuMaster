# Right Click Master

<p align="center">
  <img src="icon.png" width="128" height="128" alt="Right Click Master icon">
</p>

<p align="center">
  <strong>One small, native right-click toolkit for Finder.</strong><br>
  <a href="README_CN.md">简体中文</a>
</p>

> macOS Version 2 is implemented and locally accepted. A public DMG must still be produced by the release workflow with Developer ID and Apple notarization credentials.

Right Click Master adds four predictable actions to macOS Finder without changing your system defaults:

- New File
- Copy Path
- Open in your preferred terminal
- Open in your preferred editor

Ghostty and CotEditor are detected when installed. Terminal and editor choices remain configurable.

## Product principles

- Native Finder context menu
- Local-only operation; no account, telemetry, or path upload
- No arbitrary scripts or destructive quick actions
- No Accessibility, Screen Recording, Full Disk Access, or administrator permission
- Never overwrite an existing file
- English and Simplified Chinese interfaces

The exact context semantics, onboarding flow, and acceptance criteria live in [PRODUCT.md](PRODUCT.md). Architecture and trust boundaries are documented in [docs/architecture.md](docs/architecture.md) and [docs/security-and-release.md](docs/security-and-release.md).

## Repository layout

```text
MainApp/          macOS SwiftUI host
FinderExtension/ macOS Finder Sync extension
Shared/           shared macOS domain code, schemas, and fixtures
Tests/            macOS tests
docs/             architecture, security, and decisions
scripts/          local development and release checks
```

## macOS development

Requirements: macOS 14.5+, Xcode 26.3+, and [XcodeGen 2.45.4](https://github.com/yonaskolb/XcodeGen/releases/tag/2.45.4).

```bash
xcodegen generate
xcodebuild \
  -project RightMenuMaster.xcodeproj \
  -scheme RightMenuMaster \
  -configuration Debug \
  test
```

To install a clearly separated local development build and register its Finder extension:

```bash
APPLE_TEAM_ID="YOUR_TEAM_ID" make install-debug
```

The script preserves code signatures and installs `RightClickMaster Dev.app`. Development artifacts are not suitable for redistribution.

For end-user installation, permissions, and troubleshooting, see the [macOS installation guide](docs/install-macos.md).

## Windows status

Windows is not supported, built, tested, packaged, or released in Version 2.

## Distribution and security

A public macOS release must be signed with Developer ID, use Hardened Runtime, be notarized by Apple, and carry a stapled ticket. GitHub distribution does **not** remove these requirements.

This project never asks users to remove quarantine attributes or disable Gatekeeper. See [docs/security-and-release.md](docs/security-and-release.md) for the release gates.

## License

MIT
