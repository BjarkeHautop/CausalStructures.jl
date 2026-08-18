# CausalStructures changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.1] - 2026-18-10

### New features

- `d_separated`, `m_separated`, `minimal_separator` (`DAG`), and the backdoor/frontdoor/adjustment-set functions now accept a `Vector{Symbol}` (in addition to a single `Symbol`) for `x`/`y`, for querying sets of treatments/outcomes.
- Added `id`/`idc` (Shpitser & Pearl's identification algorithm) for `DAG`/`ADMG`.
- Added `possible_parent_sets`, the graph half of the local IDA algorithm, for `AbstractPDAG`.
- Added `backdoor_set` (Generalized Backdoor Criterion, Maathuis & Colombo 2015) for `DAG`, `CPDAG`, `MAG`, and `PAG`.
- Added `possible_optimal_adjustment_sets` (O-set-based IDA) and `possible_joint_parent_sets` (joint-IDA) for `AbstractPDAG`.
- Added `possible_d_sep` (D-SEP) for `AbstractAG`.
- Added `possible_local_structures` and `maximal_local_mag` (Wang, Qin & Zhou 2023) for `PAG`.
- Added `pagcauses` (PAGcauses, Wang, Tao, Qin & Zhou 2025), finding every valid adjustment set for a `PAG` without enumerating MAGs.

- New plot features:
  - `plot` gained `node_shape` (`:round` or `:box`), per node or for the whole graph. Both shapes are fitted to their label but rounded out to equal sides unless the label is oblong, so short labels give circles and squares while long ones give ellipses and rectangles. Edges clip to (and route around) the shape actually drawn.
  - `plot` gained `node_linestyle`, for dashed or dotted node borders.
  - `plot` gained `labels`, overriding the text drawn in each node, so labels can carry spaces, subscripts, or several lines.
  - `plot`'s `layout` keyword now also accepts a `Dict` of positions keyed by node name, not just a `Vector` in `nodes(cg)` order.
  - `plot` gained `curvature`, bowing an edge into an arc by a signed fraction of its length; per edge, per edge type, or for the whole graph. An explicitly curved edge overrides the automatic obstacle routing and parallel-edge fanning.
  - `plot`'s per-edge style `Dict`s accept a `CausalEdge` key (e.g. `bidirected(:X, :Y)`) naming one exact edge, which is what separates the two edges of an `ADMG`'s shared pair. A `(src, dst)` tuple key now names an unordered node pair, matching either way round, so styling no longer requires knowing which way an edge is stored.

### Bug fixes

- Parallel edges are now rejected on construction for every graph class except `UNKNOWN`; previously `cgraph("X --> Y, X --> Y"; class = DAG)` and friends were accepted.
- `possible_ancestors`/`possible_descendants` on `MPDAG` could include nodes only reachable via a partially directed cycle introduced by background knowledge; this also affected `is_valid_adjustment`/`all_adjustment_sets` on `MPDAG`.

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
