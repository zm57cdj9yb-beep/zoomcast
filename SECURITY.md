# Security Policy

## Local Execution & Script Trust Model

ZoomCast runs 100% offline with zero telemetry or network requests. However, `.zoomcast` workspace files can contain `Run Shell Script` actions and destructive rules (`Move to Trash`):

- **Dry-Run Preview First:** ZoomCast always previews exact `before -> after` destinations before you click **Run Rules**.
- **Safe Trash Only:** ZoomCast uses `FileManager.default.trashItem(at:resultingItemURL:)` rather than permanent deletion, and records reversible move/rename/tag operations in its Undo journal.
- **Shell Script Actions:** `Run Shell Script` executes `/bin/zsh -c` with the current user's OS privileges (guarded by a 10-second timeout). Never import and run an uninspected `.zoomcast` file from an untrusted source.
- **Path Traversal Protection:** `TokenExpander.sanitizeFileName` and `sanitizeRelativeSubfolder` strip `..` and disallowed path separators before writing.

## Reporting a Vulnerability

Please report security issues privately via GitHub's **Security -> Report a vulnerability** tab rather than opening a public issue.
