# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**du.el** is an Emacs Lisp package that provides an interactive disk usage analyzer. It runs the `du` shell command and displays results in a ctable-based interface with sorting, navigation, and file deletion capabilities.

## Development Commands

```sh
# Install dependencies (clones to ~/.emacs.d/lisp/)
make solve-dependencies

# Run tests
make test
```

Dependencies are defined in `dependencies.txt` (currently: `emacs-ctable`). The `dependencies.sh` script clones each dependency to `~/.emacs.d/lisp/`.

## Architecture

### Core Components

- **du.el** - Main package file containing:
  - `du-cell` class: Represents a table cell with parsed value and header metadata
  - `du-header` class: Defines column configuration (title, ctable model, parser, formatter, sorter)
  - `du` function: Entry point that runs `du-command` asynchronously and displays results
  - `du-ctable-show`: Renders data in a ctable buffer with click handlers
  - `du-actions`: Transient menu for row actions (delete, sort, enter directory)

### Data Flow

1. `du` executes `du-command` (default: `du -b --max-depth=1`) asynchronously
2. Output is parsed by `du-output-parser` into rows of `du-cell` objects
3. `du--to-ctable-data` applies formatters and sorts by `du--sort-col`
4. Results displayed via `ctbl:create-table-component-region`
5. User interactions handled via transient menu bound to click events

### Key Variables

| Variable | Purpose |
|----------|---------|
| `du-command` | Shell command for disk usage (default: `du -b --max-depth=1`) |
| `du-headers` | List of `du-header` objects defining table columns |
| `du-output-parser` | Function to parse raw du output |
| `du--sort-col` | Current header used for sorting |

### User Commands

- `M-x du` - Run disk usage analysis on a directory
- `RET` in table - Enter selected directory
- `d` in table - Delete selected file/directory
- `s` in table - Sort by column

## File Structure

```
du.el/
├── du.el              # Main package
├── dependencies.txt   # List of dependency repo URLs
├── dependencies.sh    # Shell script to clone dependencies
├── Makefile           # Build/test targets
├── tests/tests.el     # Test file
└── README.org         # Documentation (EN/ZH)
```
