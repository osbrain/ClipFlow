# Encrypted Backup Import Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local password-encrypted export/import for ClipFlow history using safe merge semantics.

**Architecture:** Storage owns the archive format and repository snapshot import/export. AppKit panels and password prompts live in `ClipFlowApp`, while Settings exposes the entry points. Tests drive the archive codec, repository merge behavior, and Settings UI/localization surface.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, CryptoKit AES-GCM/HMAC-SHA256, SQLCipher-backed repository, Swift Testing.

---

### Task 1: Encrypted backup codec and repository snapshot

- [ ] Write failing storage tests for encrypted export, wrong password rejection, and merge import.
- [ ] Implement backup archive models and `EncryptedBackupCodec`.
- [ ] Add repository snapshot export/import APIs.
- [ ] Run `swift run ClipFlowCoreTests`.

### Task 2: Settings UI and app integration

- [ ] Add a backup Settings category and localized strings.
- [ ] Add Settings callbacks for export/import.
- [ ] Implement AppKit save/open panels and password prompts in `ClipFlowApp`.
- [ ] Refresh the main model after successful import.

### Task 3: Verification and packaging

- [ ] Run `swift run ClipFlowCoreTests`.
- [ ] Run `swift build`.
- [ ] Run `plutil -lint` for localization files.
- [ ] Run `git diff --check`.
