# CausalStructures changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.2.0 - 2026-08-04

### Breaking changes

- Dropped the `simple` keyword argument from `cgraph`.
- Changed default layout to `:stress` once NetworkLayout is loaded.

### New features

- Implement separation for PAGs.

- Extend adjustments to include DAG.

- Add `class = PAG` support to `generate_graph`.

- Make `enumerate_mags` use several threads if available.

### Other changes

- Improved and extended docs, and uses DocumenterCodeBlocks now.

## 0.1.0 - 2026-07-25

Initial release.
