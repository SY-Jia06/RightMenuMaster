# RightMenu Master

RightMenu Master is a macOS Finder right-click enhancement app built with SwiftUI and a Finder Sync Extension. It adds configurable Finder context-menu actions such as creating files, copying paths, deleting items, and opening Terminal in the selected directory.

Current development target: macOS 14.5+.

## Current Status

The core Finder menu action chain is working in the current codebase:

- **New File**: Click "New File" directly creates a Markdown file by default. Submenu provides other templates (txt, swift, py, js, sh).
- **One-time Authorization**: First run automatically prompts for home folder access. Click "Quick Setup" in Permissions tab to authorize common folders (工作区, Documents, Desktop, Downloads).
- **Auto Rename**: After file creation, automatically enters rename mode (requires Accessibility permission). Selects filename only, excluding extension.
- Copy File Path and Copy File Name work from selected Finder items.
- Quick Delete uses `FileManager.trashItem` with persistent folder authorization.
- Open Terminal is routed through the main app command bridge, with smart directory resolution.
- Permission failure triggers main-app authorization flow with automatic retry and file creation.

Latest local verification:

```bash
xcodebuild -scheme RightMenuMaster -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Expected result: `41 tests, 0 failures`.

## Features

### Finder Actions

| Action | Current behavior |
| --- | --- |
| New File | Creates a file from a template. If the target folder needs permission, the main app asks for folder access once and then retries creation. |
| Copy File Path | Copies selected item paths to the pasteboard. |
| Copy File Name | Copies selected item names to the pasteboard. |
| Open Terminal Here | Opens Terminal at the selected folder, selected file's parent, or current Finder window directory. |
| Open iTerm Here | Same target-directory resolution as Terminal, routed through the main app bridge. |
| Quick Delete | Moves selected items to Trash using persistent security-scoped folder access when needed. |
| Move To... | Moves selected items to configured folders. |
| Copy To... | Copies selected items to configured folders. |
| Lock File | Sets selected items as user-immutable. |
| Show File Info | Opens Finder's Get Info window for the selected item. |
| Make Alias | Creates a Desktop symlink for selected items. |
| Share via QR Code | Shows a QR code for the selected item's URL. |
| Set Folder Icon Color | Tints selected folder icons. |
| Run Script | Runs a configured shell script at the target directory. |

### Built-in File Templates

| Template | Extension | Content |
| --- | --- | --- |
| Plain Text | `.txt` | Empty |
| Markdown | `.md` | `# ` header |
| Swift File | `.swift` | `import Foundation` |
| Python File | `.py` | shebang + `main()` scaffold |
| JavaScript File | `.js` | shebang |
| Shell Script | `.sh` | `set -euo pipefail` |

### Settings UI

The SwiftUI app has four tabs:

- Menu Items: enable, disable, rename, reorder, add, and remove actions.
- Templates: view built-in templates and manage custom templates.
- Scripts: edit shell scripts for the Run Script action.
- Permissions: manage persistent folder permissions and Accessibility permission for rename mode.

## Usage

### First Run Setup

1. Build and run `RightMenuMaster` from Xcode
2. Enable the Finder extension:
   ```bash
   pluginkit -e use -i com.rightmenu.master.finder-extension
   ```
   Or via System Settings: General → Login Items & Extensions → Finder Extensions → RightMenu Master

3. **Grant Folder Access** (one-time setup):
   - On first launch, the app will automatically prompt you to select your home folder (`/Users/your-username`)
   - This grants RightMenu Master access to all your user folders
   - Alternatively, click "Quick Setup" in the Permissions tab to authorize specific folders (工作区, Documents, Desktop, Downloads)

4. **Enable Auto Rename** (optional):
   - Go to Permissions tab → Click "Enable Rename"
   - Grant Accessibility permission in System Settings
   - Files will automatically enter rename mode after creation

### Daily Use

- **Create Markdown**: Right-click in Finder → New File (creates `untitled.md`)
- **Create Other Files**: Right-click → New File → Select template from submenu
- **Auto Rename**: After creation, filename is selected (without extension) for quick renaming

### Permission Notes

This is a macOS sandbox requirement. A third-party app cannot silently grant itself write access to arbitrary folders. You must authorize folders once through the system folder picker.

When New File hits an unauthorized directory, the app will:
1. Launch the main app (if not running)
2. Show a folder picker for authorization
3. Save the permission as a security-scoped bookmark
4. Automatically create the file
5. Enter rename mode

## Build

Open and build the checked-in Xcode project:

```bash
open RightMenuMaster.xcodeproj
```

In Xcode:

1. Select the `RightMenuMaster` scheme.
2. Select destination `My Mac`.
3. Confirm Signing & Capabilities for both `RightMenuMaster` and `FinderExtension`.
4. Run with `Cmd+R`.

For tests:

```bash
xcodebuild -scheme RightMenuMaster -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO
```

Do not run `xcodegen generate` casually. The checked-in `.xcodeproj` has manual signing and test-target wiring that can drift from `project.yml`. Only regenerate if you are intentionally updating project generation and then re-check the diff carefully.

## Architecture

```
Finder right-click
  -> FinderExtension/FinderSync.swift
  -> tag-indexed NSMenuItem selectors on FinderSync
  -> ActionDispatcher.shared
  -> action handler

Main app command bridge
  -> rightmenumaster://open-terminal
  -> rightmenumaster://open-iterm
  -> rightmenumaster://rename
  -> rightmenumaster://authorize-create-file
  -> MainApp/App.swift AppDelegate AppleEvent handler
```

Important files:

- `FinderExtension/FinderSync.swift`: builds menus for item and container context menus, caches target URLs and selected URLs, and refreshes monitored directories.
- `FinderExtension/ActionHandlers/ActionDispatcher.swift`: routes Finder actions and resolves target directories.
- `FinderExtension/ActionHandlers/FileCreator.swift`: creates files directly when possible and falls back to a pending authorization/create request.
- `MainApp/App.swift`: handles command URLs silently through `NSAppleEventManager`; avoids opening the SwiftUI window for internal commands.
- `MainApp/ViewModels/SettingsViewModel.swift`: manages app config, folder authorization, and Accessibility permission.
- `Shared/Constants.swift`: shared command URL helpers, authorized-folder store, pending-create store, file naming, and target-directory resolution.
- `Shared/Extensions/UserDefaults+Shared.swift`: app-group persistence for config, templates, and authorized folders.

## Permission Model

RightMenu Master has two sandboxed processes:

- Main app: SwiftUI settings app and command bridge.
- Finder extension: Finder Sync extension running in a separate sandboxed XPC process.

They communicate through:

- App Group UserDefaults: config, templates, authorized folder bookmarks, pending file creation requests.
- Custom URL scheme: `rightmenumaster://...` command bridge.
- Distributed notifications: refresh Finder extension monitored directories after permission changes.

Folder writes use security-scoped bookmarks. The extension first tries to write directly. If macOS denies access, it asks the main app to request a user-selected folder grant, stores that bookmark, and retries from the main app.

Rename mode needs Accessibility permission because it selects the newly created file in Finder and posts Return to enter rename mode. Without Accessibility permission, file creation still works, but automatic rename is skipped.

## Recent Improvements (2026-05-15)

- **Default Markdown Creation**: Click "New File" directly creates Markdown without submenu selection
- **First-run Authorization**: Automatically prompts for home folder access on first launch
- **Quick Setup Button**: One-click authorization for common folders (工作区, Documents, Desktop, Downloads)
- **Auto Rename Enhancement**: Increased delays (1.0s) for more reliable rename mode entry
- **Filename Selection**: Only selects filename portion, excluding extension (e.g., `untitled` not `untitled.md`)
- **Authorization Flow Fix**: Properly saves and notifies extension after folder authorization
- **Main App Launch**: Ensures main app is running before sending command URLs
- **Detailed Logging**: Added comprehensive logs for debugging authorization and file creation

## Fixed Bugs

- Menu items displayed but clicks did nothing. Fixed by keeping selectors on the Finder Sync principal class, using tag-based indexing instead of `representedObject`, and avoiding custom menu-item targets across the Finder Sync XPC menu boundary.
- New File wrote to the wrong folder in icon/grid layout. Fixed by distinguishing item context menus from container/background context menus.
- New File and Delete failed in sandboxed folders. Fixed with persistent security-scoped folder bookmarks and a main-app authorization retry flow for New File.
- Finder AppleScript failed with `Finder error -600`. Removed Finder AppleScript dependency for New File and Delete.
- Open Terminal failed from the extension. Fixed by delegating Terminal/iTerm launch to the main app command bridge.
- New File command opened the main GUI every time. Fixed by replacing SwiftUI `.onOpenURL` handling with an AppDelegate AppleEvent URL handler and limiting the settings `WindowGroup` to `settings` external events.
- Rename checked Accessibility permission in the extension process. Fixed by moving rename automation to the main app process.
- **Authorization not persisting**: Fixed by ensuring `authorizedFolders` array assignment triggers `didSet` for UserDefaults save.
- **Command URL not handled**: Fixed by launching main app before opening command URLs.

## Known Bugs / Risks

- First-time folder authorization still requires a system folder picker. This is not avoidable under macOS sandboxing. The user must choose the target folder or a parent folder once.
- Finder Sync menu visibility depends on monitored directories. The app monitors common roots plus authorized folders, but Finder may need extension reload or Finder restart after major build/signing changes.
- Automatic rename depends on Accessibility permission for `RightMenu Master`. If permission is missing or stale, the file is created but rename mode is skipped.
- Open Terminal uses `/usr/bin/open -a Terminal <path>` from the main app. If Terminal still fails on another machine, check whether the app command URL reaches `MainApp command open-terminal` in Console logs.
- `Move To...`, `Copy To...`, `Lock File`, `Show File Info`, `Make Alias`, `Set Folder Icon Color`, and `Run Script` have less real-world testing than New File, Delete, Copy Path, Copy Name, and Open Terminal.
- `project.yml` may not fully represent the current checked-in `.xcodeproj`. Treat project regeneration as a separate maintenance task.
- Distribution is not finished. A proper release needs Developer ID signing, notarization, hardened runtime review, and a clean first-run onboarding flow.

## TODO

- Add a first-run onboarding screen that checks Finder Extension enabled state, folder authorization, and Accessibility permission.
- Add a visible status indicator for command URL registration and app-group access.
- Add a packaging/release script for Developer ID signing, notarization, and DMG/zip creation.
- Add manual QA checklist for Downloads, Desktop, Documents, `/Users/<user>/工作区`, external volumes, selected folder, selected file, and Finder background menu.
- Add user-facing error notifications when command bridge, authorization, Terminal launch, or rename automation fails.
- Add focused integration tests or scripted manual tests for Open Terminal and New File authorization retry on a clean macOS user account.
- Review and harden less-tested actions: Move To, Copy To, Lock File, Set Folder Icon Color, and Run Script.
- Decide whether `project.yml` remains authoritative; if yes, sync it with the checked-in `.xcodeproj`.

## Debugging

Use Console.app and filter for:

```text
RightMenu
```

Important log checkpoints:

- `monitored directories=[...]`: Check if your home folder or authorized folders are in the list
- `menu kind=... target=... selected=...`: Finder extension saw the right-click and cached target context
- `dispatch: ...`: a menu action reached `ActionDispatcher`
- `createFile directoryURL: ...`: New File target resolution result
- `File create failed: ...`: direct extension write failed (triggers authorization flow)
- `Requesting app authorization for file creation at: ...`: extension handed off to main app
- `authorizeHomeFolder: home=...`: First-run authorization started
- `User selected folders: [...]`: User completed folder selection
- `Authorized paths: [...]`: Final list of authorized folders saved
- `MainApp command authorize-create-file`: main app received command URL
- `MainApp created file: ...`: main app completed authorization retry
- `MainApp rename Return key posted`: rename automation triggered
- `MainApp rename skipped: Accessibility permission is not granted`: rename needs Accessibility permission

### Common Issues

**Menu doesn't appear**: Check `monitored directories` includes your current folder or a parent folder.

**Permission keeps asking**: Check Console logs for "Authorized paths" to verify folders are being saved. Ensure App Group is configured correctly.

**File not created after authorization**: Check for "MainApp command authorize-create-file" log. If missing, main app may not be running or URL scheme not registered.

**Rename doesn't work**: Check for "Accessibility permission is not granted" log. Grant permission in System Settings → Privacy & Security → Accessibility.

## Project Structure

```
RightMenuMaster/
├── MainApp/
│   ├── App.swift
│   ├── ContentView.swift
│   ├── Info.plist
│   ├── RightMenuMaster.entitlements
│   ├── Services/
│   ├── ViewModels/
│   └── Views/
├── FinderExtension/
│   ├── FinderSync.swift
│   ├── MenuBuilder.swift
│   ├── Info.plist
│   ├── FinderExtension.entitlements
│   └── ActionHandlers/
├── Shared/
│   ├── Constants.swift
│   ├── Extensions/
│   └── Models/
├── Tests/
├── Templates/
├── RightMenuMaster.xcodeproj/
├── project.yml
└── README.md
```

## License

MIT
