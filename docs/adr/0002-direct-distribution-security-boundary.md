---
status: accepted
---

# Sandbox both macOS processes and move mutations to the host

Both the macOS host and Finder extension use App Sandbox. The extension only resolves context and writes a short-lived App Group request, while the host handles explicit file creation after the user grants Home or working-folder access through a security-scoped bookmark. This adds one transparent folder-selection step but removes Accessibility, Full Disk Access, the legacy root-scoped temporary exception, scripts, quick delete, and arbitrary destructive automation.
