# RightMenu Master

<p align="center">
  <img src="icon.png" width="128" height="128" alt="RightMenu Master Icon">
</p>

<p align="center">
  <strong>A macOS Finder right-click enhancement tool</strong><br>
  <a href="README_CN.md">中文文档</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.5%2B-blue" alt="macOS 14.5+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/github/license/SY-Jia06/RightMenuMaster" alt="MIT License">
</p>

RightMenu Master adds powerful context-menu actions to macOS Finder via a Finder Sync Extension. Create files, copy paths, open Terminal, delete items — all from a right-click.

## Features

| Action | Description |
| --- | --- |
| **New File** | Create files from templates (Markdown, Swift, Python, JS, Shell, Plain Text). Click directly for Markdown, or use submenu for others. |
| **Copy File Path** | Copy full paths of selected items to clipboard |
| **Copy File Name** | Copy filenames of selected items to clipboard |
| **Open Terminal Here** | Open Terminal.app at the current directory |
| **Open iTerm Here** | Open iTerm2 at the current directory |
| **Quick Delete** | Move selected items to Trash |
| **Auto Rename** | Automatically enters rename mode after file creation (requires Accessibility permission) |

### Built-in Templates

| Template | Extension | Content |
| --- | --- | --- |
| Plain Text | `.txt` | Empty |
| Markdown | `.md` | `# ` header |
| Swift File | `.swift` | `import Foundation` |
| Python File | `.py` | shebang + `main()` scaffold |
| JavaScript File | `.js` | shebang |
| Shell Script | `.sh` | `set -euo pipefail` |

## Installation

### Download (Recommended)

1. Download `RightMenuMaster-v1.0.0.dmg` from [Releases](https://github.com/SY-Jia06/RightMenuMaster/releases)
2. Open the DMG and drag `RightMenuMaster.app` to `/Applications`
3. Remove quarantine (required for unsigned apps):

   ```bash
   xattr -cr /Applications/RightMenuMaster.app
   ```

4. Open the app
5. Enable the Finder extension: **System Settings → General → Login Items & Extensions → Finder Extensions → RightMenu Master**

   Or via command line:

   ```bash
   pluginkit -e use -i com.rightmenu.master.finder-extension
   ```

### Build from Source

```bash
git clone https://github.com/SY-Jia06/RightMenuMaster.git
cd RightMenuMaster
open RightMenuMaster.xcodeproj
```

In Xcode: select `RightMenuMaster` scheme → My Mac → Run (Cmd+R).

## Usage

- **Create Markdown**: Right-click in Finder → **New File** (creates `untitled.md`)
- **Create Other Files**: Right-click → **New File** → hover submenu → select template
- **Copy Path**: Right-click a file → **Copy File Path**
- **Open Terminal**: Right-click a folder → **Open Terminal Here**
- **Delete**: Right-click → **Quick Delete**

### Auto Rename (Optional)

After creating a file, RightMenu Master can automatically enter rename mode (filename selected, extension excluded). To enable:

1. Open RightMenu Master settings (click menu bar icon → Open Settings)
2. Go to Permissions tab → Click "Enable Rename"
3. Grant Accessibility permission in System Settings

## Settings

The app provides a settings UI accessible from the menu bar icon:

- **Menu Items**: Enable, disable, rename, and reorder context menu actions
- **Templates**: Manage custom file templates
- **Scripts**: Edit shell scripts for the Run Script action
- **Permissions**: Manage folder access and Accessibility permission

## Architecture

```text
Finder right-click
  → FinderSync.swift (Finder Sync Extension)
  → ActionDispatcher (routes actions)
  → FileCreator / PathCopier / ScriptRunner

Main app (command bridge)
  → rightmenumaster:// URL scheme
  → AppCommandHandler (Terminal, iTerm, Rename, Trash)
  → Menu bar status item (settings UI)
```

Communication between extension and main app:
- **App Group UserDefaults**: shared config and templates
- **Custom URL scheme**: `rightmenumaster://` command bridge
- **Distributed notifications**: refresh monitored directories

## Known Limitations

- **iCloud Drive**: Right-click menu does not appear in iCloud Drive directories (macOS Finder Sync system limitation)
- **Unsigned**: No Developer ID signature. Users must run `xattr -cr` or right-click → Open on first launch
- **Auto Rename**: Requires Accessibility permission. If not granted, files are created but rename mode is skipped

## License

MIT
