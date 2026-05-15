# Implementation Plan

## Tasks

- [x] 1. Write bug condition exploration test
  - [x] 1.1 Write exploration test confirming bug conditions exist in unfixed code
  - [x] 1.2 Run exploration test and document counterexamples

- [x] 2. Write preservation property tests before implementing fix
  - [x] 2.1 Write property tests for FinderMonitorDirectories and path matching logic
  - [x] 2.2 Write property tests for FileCreationPlanner and AppCommandURL

- [x] 3. Implement sandbox permission sharing fix
  - [x] 3.1 Add RealHomeDirectory helper enum to Shared/Constants.swift
  - [x] 3.2 Replace default home parameter in FinderMonitorDirectories.urls()
  - [x] 3.3 Update makeDesktopAlias in ActionDispatcher.swift to use RealHomeDirectory.url
  - [x] 3.4 Add document-scope bookmark entitlement to both targets
  - [x] 3.5 Switch AuthorizedFolderStore.authorizeFolder to document-scoped bookmarks
  - [x] 3.6 Switch AuthorizedFolderStore.withAccess to resolve document-scoped bookmarks
  - [x] 3.7 Add bookmark migration logic for existing app-scoped bookmarks
  - [x] 3.8 Add AppCommand.trashFile command and handler
  - [x] 3.9 Add trash fallback in ActionDispatcher.trashSelectedItems
  - [x] 3.10 Verify bug condition exploration test now passes
  - [x] 3.11 Verify preservation tests still pass

- [x] 4. Checkpoint - Ensure all tests pass
