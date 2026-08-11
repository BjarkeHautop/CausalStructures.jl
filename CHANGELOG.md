# CausalStructures changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased version

### New features

- `d_separated`, `m_separated`, `minimal_separator` (`DAG`), and the backdoor/frontdoor/adjustment-set functions now accept a `Vector{Symbol}` (in addition to a single `Symbol`) for `x`/`y`, for querying sets of treatments/outcomes. `is_valid_iv`/`all_iv_sets` accept a `Vector{Symbol}` outcome `y` (the instrumental-set criterion still requires a single treatment `x`).

## [0.3.0] - 2026-08-10

### Breaking changes

- Removed the built-in `:circle` layout. `layout`/`plot` now require NetworkLayout to be loaded (or bring your own layout to plot), and default to `:stress`.

### New features

- Added `adjustment_set` for `ADMG` and `PAG`, returning the smallest valid adjustment set.
- Added `anteriors`/`posteriors` methods for `ADMG`.
- Extended `condition_marginalize` to accept `ADMG`.
- Added `check_cycles` and `r4` as keyword arguments to `meek_closure`, which can be
set to help speed it up.
- Added `node_padding` (and `"plot_node_padding"` preference) to control the padding between a node's label and its circle edge.
- Added `arrow_fill` (and `"plot_edge_arrow_fill"` preference) to style arrowheads independently of `edge_color`, including hollow/outline-only arrowheads.
- Added `fig_size` to set the plot's figure size.

### Bug fixes

- `dag_from_pdag` could pick a sink whose undirected neighbors were adjacent to each other but not to the sink's existing parents, which could make it introduce a
v-structure absent from the input PDAG.

## [0.2.0] - 2026-08-04

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

## [0.1.0] - 2026-07-25

Initial release.
