# RightMenu Master

A customizable Finder right-click menu enhancement tool for macOS 14.5+. Built with SwiftUI and Finder Sync Extension.

## Features

- **Customizable Right-Click Menu** — Choose which actions appear in Finder's context menu
- **New File Creation** — Create files from templates (.txt, .md, .swift, .py, .js, .sh) via right-click
- **Custom Templates** — Add your own file templates with custom content
- **Custom Scripts** — Run shell scripts directly from the Finder right-click menu
- **Copy Path / Name** — Quick copy file paths or names to clipboard
- **Open Terminal** — Open Terminal or iTerm at the current Finder location
- **Move To / Copy To** — Move or copy files to pre-configured folders
- **Quick Delete** — Delete files/folders directly via right-click
- **Lock Files** — Lock files to prevent accidental modification
- **Make Alias** — Create desktop shortcuts (symlinks)
- **QR Code Sharing** — Generate QR codes for selected files
- **Folder Icon Color** — Customize folder icon colors

## Requirements

- macOS 14.5 (Sonoma) or later
- Xcode 16.0 or later

## Build

```bash
# Install dependencies
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
open RightMenuMaster.xcodeproj
```

In Xcode:
1. Select **RightMenuMaster** scheme
2. **Signing & Capabilities** → select your Team
3. Product → Build (⌘B)

## Architecture

```
MainApp (SwiftUI)          FinderExtension (FIFinderSync)
    │                            │
    └──────── App Groups ────────┘
         (UserDefaults shared)
```

- **MainApp**: SwiftUI settings interface for configuring menu items, templates, and scripts
- **FinderExtension**: macOS Finder Sync Extension that injects custom menu items into Finder's right-click menu
- **Shared**: Cross-process models and utilities shared between app and extension

## Enable Extension

After building and running the app:

1. System Settings → General → Extensions → Finder Extensions
2. Enable **RightMenu Master**
3. Grant folder access when prompted

Or via terminal:
```bash
pluginkit -e use -i com.rightmenu.master.finder-extension
```

## License

MIT
