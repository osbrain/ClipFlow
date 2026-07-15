# README and Licensing Design

## Goal

Prepare ClipFlow for public hosting with clear English-first project documentation, a Chinese translation, and terms that permit personal, non-commercial use of the source while prohibiting commercial use.

## Licensing Decision

Use PolyForm Noncommercial License 1.0.0 in the root `LICENSE` file.

This is a source-available license, not an OSI-approved open-source license: OSI open-source licenses must allow commercial use. The documentation will state this distinction plainly and identify the allowed use as personal and non-commercial.

## Documentation Layout

- `README.md` is the primary English GitHub landing page.
- `README.zh-CN.md` is a Chinese translation with reciprocal language links.
- `LICENSE` contains the unmodified PolyForm Noncommercial License 1.0.0 text.

## README Content

Each language version will cover:

1. A concise description of ClipFlow as a native, privacy-first macOS clipboard manager.
2. Its implemented user-facing capabilities: clipboard history, search, keyboard-driven panel, paste modes, favorites/categories, browser-tab integration, encrypted local storage, and local-only processing.
3. macOS and toolchain prerequisites derived from `Package.swift` and the development scripts.
4. Development setup, build, test, and packaging commands using the existing scripts.
5. Privacy and permissions, including accessibility and optional browser automation.
6. Contribution expectations and a pointer to the non-commercial license.

## Scope and Validation

The change adds documentation and a license only. Validation consists of checking language links, local file references, shell commands against the existing scripts, and ensuring the license notice does not claim OSI open-source status.
