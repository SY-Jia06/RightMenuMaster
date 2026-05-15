# Sandbox Permission Sharing Fix — Bugfix Design

## Overview

The Finder Sync Extension runs in a separate sandbox container from the main app, causing three interrelated failures: (1) `homeDirectoryForCurrentUser` returns the container path instead of the real user home, (2) app-scoped security bookmarks created by the main app cannot be resolved by the extension process, and (3) the extension cannot access authorized folders, causing "New File" and "Quick Delete" to fail with permission errors.

The fix strategy is two-pronged:
- **Home path**: Replace `FileManager.default.homeDirectoryForCurrentUser` with a POSIX-based real home directory lookup (`getpwuid`) that is unaffected by sandbox containerization.
- **Bookmark sharing**: Switch from app-scoped (`.withSecurityScope`) to document-scoped bookmarks, which can be resolved by any process that has the `com.apple.security.files.bookmarks.document-scope` entitlement and access to the App Group container. Additionally, add a fallback in `trashSelectedItems` to delegate to the main app when the extension lacks permission.

## Glossary

- **Bug_Condition (C)**: The condition that triggers the bug — the Finder Sync Extension process attempts to resolve a home directory path or a security-scoped bookmark that was created by the main app process
- **Property (P)**: The desired behavior — the extension resolves the real user home and can access authorized folders via shared bookmarks
- **Preservation**: Existing behaviors that must remain unchanged — direct file creation in entitled directories (Desktop/Documents/Downloads), main app authorization flow, non-file-write operations, all 41 existing tests
- **FinderMonitorDirectories**: Enum in `Shared/Constants.swift` that computes the set of monitored directory URLs for `FIFinderSyncController`
- **AuthorizedFolderStore**: Singleton in `Shared/Constants.swift` that manages security-scoped bookmark persistence and access
- **App-scoped bookmark**: A bookmark created with `.withSecurityScope` option — only resolvable by the creating app's process
- **Document-scoped bookmark**: A bookmark created with `.withSecurityScope` + a `relativeTo` URL pointing to a shared container — resolvable by any process with access to that container
- **App Group container**: The shared `group.com.rightmenu.master` directory accessible by both main app and extension

## Bug Details

### Bug Condition

The bug manifests when the Finder Sync Extension process attempts to use paths or bookmarks that depend on the calling process's sandbox identity. Specifically: (a) `FileManager.default.homeDirectoryForCurrentUser` returns the container path `~/Library/Containers/com.rightmenu.master.finder-extension/Data` instead of `/Users/<username>`, and (b) bookmarks created with `.withSecurityScope` (app-scope) by the main app cannot be resolved by the extension because app-scoped bookmarks are bound to the creating process.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input of type (process: Process, operation: Operation)
  OUTPUT: boolean

  LET isExtensionProcess = input.process.bundleID == "com.rightmenu.master.finder-extension"

  CASE input.operation OF
    HomeDirectoryLookup:
      RETURN isExtensionProcess
             AND usesFileManagerHomeDirectory(input.operation)
    BookmarkResolve:
      RETURN isExtensionProcess
             AND input.operation.bookmarkData.scope == .appScope
             AND input.operation.bookmarkData.creatorProcess != input.process
    FileWrite:
      RETURN isExtensionProcess
             AND requiresBookmarkAccess(input.operation.targetURL)
             AND NOT hasDirectEntitlement(input.process, input.operation.targetURL)
  END CASE
END FUNCTION
```

### Examples

- **Home path in extension**: `FinderMonitorDirectories.urls()` is called with default `home` parameter → returns `Set` containing `/Users/j/Library/Containers/.../Data/Desktop` instead of `/Users/j/Desktop` → Finder does not monitor the real Desktop
- **Bookmark resolve in extension**: `AuthorizedFolderStore.withAccess(to:)` calls `URL(resolvingBookmarkData:options:.withSecurityScope)` → throws error because the bookmark was created by the main app process → `withAccess` falls through to unscoped operation → file write fails with permission error
- **New File in ~/Projects**: User right-clicks in `~/Projects` → extension calls `FileCreator.createFile` → `withAccess` fails to resolve bookmark → `data.write(to:)` throws "you don't have permission" → falls back to main app (works, but only after error)
- **Quick Delete in ~/Projects**: User right-clicks file → extension calls `trashSelectedItems` → `withAccess` fails → `trashItem` throws permission error → no fallback exists → operation fails silently

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- Direct file creation in Desktop, Documents, Downloads (extension has explicit read-write entitlements for these)
- Main app's `NSOpenPanel`-based folder authorization flow and bookmark creation
- `DistributedNotificationCenter` notification for authorized folder changes
- `PendingFileCreationRequest` storage and retrieval via App Group UserDefaults
- All non-file-write operations: Copy Path, Copy Name, Open Terminal, Open iTerm, Lock File, Show Info, Make Alias, QR Share, Set Folder Icon
- Custom script execution via `ScriptRunner`
- Move/Copy items operations
- All 41 existing tests (they inject mock home URLs and don't resolve real bookmarks)

**Scope:**
All inputs that do NOT involve the extension process resolving home directory paths or cross-process bookmark data should be completely unaffected by this fix. This includes:
- Any operation in the main app process
- Extension operations that don't require bookmark-based file access
- Extension operations in directories covered by explicit entitlements (Desktop, Documents, Downloads)

## Hypothesized Root Cause

Based on the bug description and code analysis, the root causes are:

1. **Container Home Path**: `FinderMonitorDirectories.urls()` uses `FileManager.default.homeDirectoryForCurrentUser` as its default parameter. In the extension's sandbox container, this API returns the container path (`~/Library/Containers/com.rightmenu.master.finder-extension/Data`) rather than the real user home (`/Users/j`). This causes monitored directories to point to non-existent container subdirectories.

2. **App-Scoped Bookmark Isolation**: `AuthorizedFolderStore.authorizeFolder(_:)` creates bookmarks with `.withSecurityScope` option and `relativeTo: nil`. This produces app-scoped bookmarks that are cryptographically bound to the creating process. When the extension calls `URL(resolvingBookmarkData:options:.withSecurityScope, relativeTo: nil)`, resolution fails because the bookmark belongs to a different process.

3. **Missing Trash Fallback**: `ActionDispatcher.trashSelectedItems` catches the permission error but only logs it. Unlike `FileCreator.createFile` which has `requestAuthorizationAndCreate` as a fallback, there is no mechanism to delegate the trash operation to the main app when the extension lacks permission.

4. **Missing Document-Scope Entitlement**: Neither the main app nor the extension has `com.apple.security.files.bookmarks.document-scope` in their entitlements, which is required for document-scoped bookmarks that can be shared across processes.

## Correctness Properties

Property 1: Bug Condition - Extension Resolves Real Home Directory

_For any_ call to `FinderMonitorDirectories.urls()` from the Finder Sync Extension process, the returned URL set SHALL contain paths based on the real user home directory (e.g., `/Users/j/Desktop`) rather than the sandbox container path, regardless of the calling process's sandbox containerization.

**Validates: Requirements 2.1**

Property 2: Bug Condition - Cross-Process Bookmark Resolution

_For any_ authorized folder bookmark stored by the main app, the Finder Sync Extension process SHALL be able to resolve the bookmark data and obtain a security-scoped URL that grants file system access to the authorized folder.

**Validates: Requirements 2.2, 2.3**

Property 3: Bug Condition - File Operations Succeed or Fallback

_For any_ file write operation (create or trash) triggered from the extension in a directory requiring bookmark access, the operation SHALL either succeed directly (if bookmark resolves) or fall back to the main app without displaying a user-visible error.

**Validates: Requirements 2.4, 2.5**

Property 4: Preservation - Direct Entitlement Access Unchanged

_For any_ file operation in directories where the extension has direct entitlement access (Desktop, Documents, Downloads), the fixed code SHALL produce the same result as the original code, preserving direct file creation without main app involvement.

**Validates: Requirements 3.1, 3.6**

Property 5: Preservation - Existing Tests Pass

_For any_ execution of the existing 41 test suite, all tests SHALL continue to pass without modification, since tests use injected home directory URLs and do not depend on real bookmark resolution.

**Validates: Requirements 3.7**

## Fix Implementation

### Changes Required

Assuming our root cause analysis is correct:

**File**: `Shared/Constants.swift`

**Function**: `FinderMonitorDirectories.urls(home:authorizedFolders:)`

**Specific Changes**:
1. **Replace default home parameter**: Change the default value of `home` from `FileManager.default.homeDirectoryForCurrentUser` to a new `RealHomeDirectory.url` computed property that uses `getpwuid(getuid())` to obtain the real home path unaffected by sandbox containerization.

**File**: `Shared/Constants.swift`

**Function**: `AuthorizedFolderStore.authorizeFolder(_:)`

**Specific Changes**:
2. **Switch to document-scoped bookmarks**: Change `bookmarkData(options: [.withSecurityScope], relativeTo: nil)` to `bookmarkData(options: [.withSecurityScope], relativeTo: appGroupContainerURL)` where `appGroupContainerURL` is the App Group shared container directory.

**File**: `Shared/Constants.swift`

**Function**: `AuthorizedFolderStore.withAccess(to:perform:)`

**Specific Changes**:
3. **Resolve with document scope**: Change `URL(resolvingBookmarkData:options:.withSecurityScope, relativeTo: nil)` to `URL(resolvingBookmarkData:options:.withSecurityScope, relativeTo: appGroupContainerURL)` to match the creation scope.

**File**: `FinderExtension/ActionHandlers/ActionDispatcher.swift`

**Function**: `trashSelectedItems(selectedURLs:)`

**Specific Changes**:
4. **Add fallback to main app**: When `trashItem` fails with a permission error, delegate the operation to the main app via a new `AppCommand.trashFile` URL command, similar to how `FileCreator` delegates to `authorizeCreateFile`.

**File**: `MainApp/App.swift`

**Function**: `AppCommandHandler.handle(_:)`

**Specific Changes**:
5. **Add trash command handler**: Add a new `AppCommand.trashFile` case that receives a file path, resolves the bookmark, and performs `trashItem` with the authorized access.

**File**: `FinderExtension/FinderExtension.entitlements`

**Specific Changes**:
6. **Add document-scope bookmark entitlement**: Add `com.apple.security.files.bookmarks.document-scope` → `true`.

**File**: `MainApp/RightMenuMaster.entitlements`

**Specific Changes**:
7. **Add document-scope bookmark entitlement**: Add `com.apple.security.files.bookmarks.document-scope` → `true`.

**File**: `Shared/Constants.swift`

**Specific Changes**:
8. **Add RealHomeDirectory helper**: Add a new enum `RealHomeDirectory` with a static `url` property that calls `getpwuid(getuid())?.pointee.pw_dir` and converts to a `URL`, falling back to `FileManager.default.homeDirectoryForCurrentUser` if the POSIX call fails.

**File**: `Shared/Constants.swift`

**Function**: `ActionDispatcher.makeDesktopAlias()`

**Specific Changes**:
9. **Use real home for Desktop alias**: Replace `FileManager.default.homeDirectoryForCurrentUser` with `RealHomeDirectory.url` in the `makeDesktopAlias` function to ensure aliases are created on the real Desktop.

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code, then verify the fix works correctly and preserves existing behavior.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis. If we refute, we will need to re-hypothesize.

**Test Plan**: Write tests that exercise `FinderMonitorDirectories.urls()` with the default home parameter in a sandboxed extension context, and tests that attempt to resolve app-scoped bookmarks from a different process context. Run these tests on the UNFIXED code to observe failures.

**Test Cases**:
1. **Home Path Test**: Call `FinderMonitorDirectories.urls()` with `FileManager.default.homeDirectoryForCurrentUser` in extension context — verify it returns container path (will demonstrate bug on unfixed code)
2. **Bookmark Scope Test**: Create a bookmark with `.withSecurityScope` + `relativeTo: nil` in one process, attempt to resolve in simulated different process context (will fail on unfixed code)
3. **Trash Permission Test**: Call `trashSelectedItems` for a URL in an authorized folder when bookmark resolution fails (will fail silently on unfixed code)
4. **File Creation Permission Test**: Call `FileCreator.createFile` for a URL in an authorized folder when bookmark resolution fails (will fall back to main app on unfixed code)

**Expected Counterexamples**:
- `FinderMonitorDirectories.urls()` returns URLs containing `/Library/Containers/` path segments
- `URL(resolvingBookmarkData:)` throws error code 259 (bookmark resolution failed)
- Possible causes: app-scoped bookmark isolation, missing document-scope entitlement

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds, the fixed function produces the expected behavior.

**Pseudocode:**
```
FOR ALL input WHERE isBugCondition(input) DO
  CASE input.operation OF
    HomeDirectoryLookup:
      result := FinderMonitorDirectories.urls(home: RealHomeDirectory.url, ...)
      ASSERT result contains URL("/Users/<username>/Desktop")
      ASSERT result does NOT contain "/Library/Containers/"
    BookmarkResolve:
      result := URL(resolvingBookmarkData: docScopedBookmark, relativeTo: appGroupContainer)
      ASSERT result != nil
      ASSERT result.startAccessingSecurityScopedResource() == true
    FileWrite:
      result := createFile/trashItem with fixed bookmark resolution
      ASSERT result == .success OR result == .delegatedToMainApp
  END CASE
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**
```
FOR ALL input WHERE NOT isBugCondition(input) DO
  ASSERT originalFunction(input) = fixedFunction(input)
END FOR
```

**Testing Approach**: Property-based testing is recommended for preservation checking because:
- It generates many test cases automatically across the input domain (various directory paths, template types, action types)
- It catches edge cases that manual unit tests might miss (unusual path characters, deeply nested directories)
- It provides strong guarantees that behavior is unchanged for all non-buggy inputs

**Test Plan**: Observe behavior on UNFIXED code first for operations that don't involve bookmark resolution (Copy Path, Copy Name, direct-entitlement writes), then write property-based tests capturing that behavior.

**Test Cases**:
1. **Direct Entitlement Preservation**: Verify file creation in Desktop/Documents/Downloads continues to work directly without main app involvement
2. **Non-Write Operation Preservation**: Verify Copy Path, Copy Name, Open Terminal, etc. continue working identically
3. **Main App Authorization Flow Preservation**: Verify the existing `authorizeCreateFile` command flow continues to work
4. **Notification Preservation**: Verify `DistributedNotificationCenter` authorized folder change notifications continue to trigger directory refresh

### Unit Tests

- Test `RealHomeDirectory.url` returns a path matching `/Users/<username>` pattern
- Test `FinderMonitorDirectories.urls(home: RealHomeDirectory.url)` produces correct directory set
- Test `AuthorizedFolderStore.authorizeFolder` creates document-scoped bookmark with correct `relativeTo`
- Test `AuthorizedFolderStore.withAccess` resolves document-scoped bookmark with correct `relativeTo`
- Test `ActionDispatcher.trashSelectedItems` falls back to main app command on permission error
- Test `AppCommandHandler` handles new `trashFile` command correctly
- Test bookmark migration: old app-scoped bookmarks are re-created as document-scoped on first load

### Property-Based Tests

- Generate random valid directory paths and verify `FinderMonitorDirectories.urls()` never contains container path segments
- Generate random `AuthorizedFolderGrant` arrays and verify `authorizedFolder(containing:in:)` logic is unchanged (pure path matching, no bookmark resolution)
- Generate random `MenuAction` types and verify non-file-write actions dispatch identically to original code
- Generate random `FileTemplate` + directory combinations and verify `FileCreationPlanner.nextFileURL` is unchanged

### Integration Tests

- Test full flow: main app authorizes folder → bookmark stored → extension resolves bookmark → file created successfully
- Test full flow: extension fails to write → delegates to main app → main app creates file → rename triggered
- Test full flow: extension fails to trash → delegates to main app → main app trashes file
- Test authorized folder change notification triggers extension directory refresh with correct real-home-based paths
