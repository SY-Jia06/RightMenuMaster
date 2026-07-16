# Right Click Master v2 Product Specification

## Promise

Right Click Master is a local-first, open-source action layer for macOS Finder. It gives Mac users four reliable context-menu actions without changing system defaults or teaching users to bypass platform security.

## Supported Platforms

- macOS 14.5 or later, Apple silicon and Intel
- Simplified Chinese and English

Windows is not supported in Version 2 and is outside current build, test, packaging, and release criteria.

## Version 2 Scope

1. New File
2. Copy Path
3. Open in Preferred Terminal
4. Open in Preferred Editor

The context menu contains one native `Right Click Master` submenu. Application names are dynamic, for example `Open in Ghostty` and `Open with CotEditor`.

Version 2 does not expose shell scripts, quick delete, move/copy automation, arbitrary executable templates, menu themes, accounts, analytics, or cloud sync. Legacy data remains readable for migration but risky actions are not offered by default.

## Context Semantics

| Invocation Context | New File | Copy Path | Terminal | Editor |
| --- | --- | --- | --- | --- |
| Folder background | Visible directory | Visible directory | Visible directory | Visible directory |
| One file | Parent directory | File | Parent directory | File |
| One folder | Folder | Folder | Folder | Folder |
| Same-parent selection | Common parent | Every subject, one path per line | Common parent | Every subject when supported |
| Mixed-parent selection | Disabled | Every physical path | Disabled | Enabled only when the editor supports it |
| Virtual location without a path | Disabled | Disabled | Disabled | Disabled |

Paths remain lexical and are not resolved through symbolic links. Read-only directories still allow Copy Path, Terminal, and Editor. New File never overwrites an existing entry.

## First-Run Experience

The native window is approximately 560 by 440 points and resumes after interruption.

1. **Welcome** — short product promise and `Runs locally. No account required.`
2. **Choose tools** — detect installed terminals and editors; prefer Ghostty and CotEditor when present. The user can change either choice. This never changes system defaults.
3. **Enable integration** — open the Finder extension settings and show live state instead of prose-only instructions.
4. **Verify** — test extension-to-host communication and a create/remove cycle inside app-owned temporary storage, then open a safe test folder.

Normal setup asks the user to enable the Finder extension and select Home or specific working folders with the system folder picker. Right Click Master does not request Accessibility, Screen Recording, Full Disk Access, or administrator access.

## New File Panel

Invoking New File opens one native panel centered on the active display:

- Working Directory, shortened for display but available to assistive technology
- Focused filename field
- File Recipe choices: Blank, Text (`.txt`), Markdown (`.md`)
- `Open with <Preferred Editor> after creating` option
- Cancel and Create buttons; Return creates and Escape cancels

Rules:

- An explicit extension wins over the selected recipe.
- Dotfiles such as `.env` remain extensionless.
- Creation uses an exclusive atomic operation and never overwrites.
- A collision suggests the next available name but does not silently choose it.
- If creation succeeds and editor launch fails, retrying only reopens the existing file.
- Invalid names, missing directories, and denied writes receive specific repair text.

## Settings

Settings uses a native sidebar with three destinations:

- **Actions** — enable and order four actions; choose default File Recipe and post-create behavior.
- **Applications** — choose Preferred Terminal and Preferred Editor from detected applications or a user-selected application.
- **System** — Integration Health, repair, language, privacy, diagnostics, version, and GitHub link.

Settings save immediately. Diagnostics exclude usernames, filenames, and paths unless the user explicitly includes them.

## Visual System

- Native system font and controls: SwiftUI and SF Symbols.
- System backgrounds and accent colors; no fixed brand-blue dependency.
- Eight-point spacing grid, 10–12 point card radius, restrained 120–160 ms state transitions.
- Light, dark, increased-contrast, reduced-motion, keyboard, and VoiceOver support.
- Status always combines icon and text; color is never the only signal.
- Context menus remain native. Visual character belongs in onboarding, settings, iconography, and the New File panel.

## Privacy and Security

- No account, telemetry, path upload, or directory scanning.
- Both macOS processes use App Sandbox. Persistent write access comes only from user-selected security-scoped bookmarks.
- The app and Finder extension have no network entitlement and perform no network requests.
- The Finder extension never runs scripts, performs network requests, or hosts a cross-platform runtime.
- File paths are structured arguments, never interpolated into a shell command.
- Public macOS artifacts are Developer ID signed, Hardened Runtime enabled, notarized, and stapled.
- Documentation never recommends `xattr -cr`, disabling Gatekeeper, or trusting a self-signed production certificate.

## Acceptance Criteria

- A new user reaches a working context menu within two minutes.
- All four actions match the context table in every supported Finder invocation context.
- New File cannot overwrite an existing file under concurrent invocation.
- Main settings window may quit while shell actions remain available on demand.
- Interrupted onboarding resumes.
- Integration Health does not alter clipboard, launch another app, or inspect user folders.
- Uninstall removes shell menu entries and leaves no resident process.
- English, Simplified Chinese, light, dark, high-contrast, and keyboard-only flows remain usable without clipping.
