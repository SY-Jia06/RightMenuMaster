# Right Click Master

Right Click Master provides a small, consistent action layer inside macOS Finder. This glossary keeps user-facing language aligned across the Finder extension, host app, documentation, and diagnostics.

## Language

**Invocation Context**:
The file-manager location and selection from which the user opens the Right Click Master menu.
_Avoid_: Context, current folder

**Subject**:
The file or folder an action directly operates on. A multi-selection may contain several subjects.
_Avoid_: Target, item

**Working Directory**:
The single physical directory used by New File and Open in Terminal after resolving an Invocation Context.
_Avoid_: Target folder, current path

**Action**:
One of the four supported user intents: New File, Copy Path, Open in Terminal, or Open in Editor.
_Avoid_: Command, script, verb

**Preferred Terminal**:
The installed terminal chosen for Right Click Master actions without changing any operating-system default.
_Avoid_: Default terminal

**Preferred Editor**:
The installed editor chosen for Right Click Master actions without changing file associations.
_Avoid_: Default editor

**System Association**:
The operating system's application association for a particular file type.
_Avoid_: Preferred Editor

**File Recipe**:
A safe built-in file kind consisting of a suggested extension and initial content.
_Avoid_: Script, executable template

**Integration Health**:
The verified state of the shell extension, its communication with the host app, and configured application availability.
_Avoid_: Permission status, install status
