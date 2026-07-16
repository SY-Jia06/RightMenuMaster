# Architecture

## Shape

Right Click Master uses a native Finder extension and a native macOS host app. Action semantics, request/configuration schemas, and fixtures stay independent from presentation code without adding a cross-platform UI runtime.

```text
Finder
        |
        | native context-menu callback
        v
Finder Sync Extension
        |
        | structured request, no shell interpolation
        v
SwiftUI Host App
        |
        +-- New File panel and exclusive creation
        +-- clipboard
        +-- terminal/editor adapters
        +-- settings and health checks
```

## macOS

- SwiftUI host application
- Finder Sync extension for item and container context menus
- Shared App Group preferences for safe configuration; one-shot request files are atomically written under `ActionRequests/<UUID>.json`
- Custom URL activation wakes the host with only a request UUID; payloads never enter URLs or command lines
- Finder extension performs no file mutation and runs no external process
- Both targets use App Sandbox. The host stores app-scoped security-scoped bookmarks after the user selects Home or working folders
- Host handles user-requested file operations without Accessibility or Full Disk Access

## Shared Contracts

Requests contain a version, unique identifier, Action, Invocation Context kind, ordered physical paths, and timestamp. Configuration contains enabled actions, action order, Preferred Terminal, Preferred Editor, File Recipe, language, and onboarding state.

The schemas are forward-compatible: readers reject unknown major versions and preserve unknown optional fields during migrations when possible. Requests expire after 30 seconds and are consumed once.

## Security Boundaries

- Shell extensions are treated as untrusted high-availability surfaces: bounded work, no network, no scripts, no destructive operations.
- The host validates every incoming path and recomputes the Working Directory rather than trusting a caller-provided directory.
- New File uses exclusive creation and never follows a caller request to overwrite.
- Terminal/editor adapters pass paths as arguments or platform-native activation objects.
- Diagnostics redact paths by default.
