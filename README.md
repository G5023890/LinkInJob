# Project Cleaner

Project Cleaner is a native macOS utility for safely cleaning build caches and temporary artifacts from development projects.

The app is designed for predictable, low-risk cleanup workflows:
- scan first,
- review exactly what will be removed,
- confirm before cleaning.

## Highlights

- Native SwiftUI app for macOS 14+
- Automatic scan on launch
- Clear summary of:
  - project size
  - selected removable size
  - estimated size after cleanup
- Finder-like cleanup list with:
  - per-item checkbox
  - Select All
  - size sorting
  - hover path preview
- Safety-first clean confirmation dialog
- Built-in script-based scanner (`safe_clean.sh`)

## Safety Model

Project Cleaner is intentionally conservative:

- Scans and cleans only inside the selected root folder
- Excludes `.git` from scan and cleanup
- Targets only known cache/build artifact patterns
- Requires explicit user confirmation before cleaning
- Never removes source code by design of the cleanup rules

## What Gets Cleaned

Typical removable artifacts include:

- Common: `node_modules`, `dist`, `build`, `.cache`, `tmp`, `.tmp`, `*.log`, `.DS_Store`
- Swift/Xcode: `.build`, local `DerivedData`, `*.xcuserstate`, `xcuserdata`
- Python: `__pycache__`, `.pytest_cache`, `.mypy_cache`, `*.pyc`
- Rust: `target`
- Go (artifact-checked): `bin`, `pkg`
- C/C++: `CMakeFiles`, `CMakeCache.txt`
- Codex: `.codex`, `.agent`

## Project Structure

```text
Sources/ProjectCleanerApp/
  ProjectCleanerApp.swift
  ProjectCleanerView.swift
  ProjectCardView.swift
  ScanResultView.swift
  CleanListView.swift
  BottomActionBar.swift
  CleanerViewModel.swift
  Models.swift
scripts/
  safe_clean.sh
  build_and_install_app.sh
assets/
  AppIcon.icns
```

## Build

```bash
swift build -c release
```

## Install to /Applications

```bash
./scripts/build_and_install_app.sh
```

This script:
- builds release binary,
- packages `.app`,
- embeds `safe_clean.sh` into app resources,
- signs the app,
- installs to `/Applications/Project Cleaner.app`.

## Run

```bash
open -a "Project Cleaner"
```

## Command Line Dry Run (Script only)

```bash
./scripts/safe_clean.sh
```

Apply cleanup after review:

```bash
./scripts/safe_clean.sh --apply
```

## Requirements

- macOS 14+
- Swift 5.9+
- Xcode Command Line Tools

## License

Add your preferred license here.
