# Changelog

## 0.3.2 - 2026-10-03

- Replaced the corrupted first shell implementation with a clean Bash rewrite.
- Added explicit model-set dependency closure.
- Added deterministic payload UUIDs.
- Added UAF live asset-type validation.
- Added model byte reporting through UAF.
- Added profile-marker state detection.
- Added legacy/upstream profile conflict detection.
- Added profile-generation self-tests.
- Added macOS CI for Bash parsing and Apple Clang compilation.
- Hardened the native XPC completion path against double completion.
