# CausalStructures changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased version

### New features

- Implemented `markov_blanket` for a `PAG`.
- `adjustment_set(::DAG)` and `adjustment_set(::AbstractPDAG)` with `type = :optimal` now warn when some node of `y` is not a (possible) descendant of `x`, since the O-set is not defined there.

### Bug fixes

- `markov_blanket` on an `AbstractAG` or `ADMG` missed nodes reachable through collider paths (e.g. `C` in `A <-> B <-> C`), so it could return a set too small to separate `node` from the rest of the graph.
- `meek_closure`'s R4 was missing the precondition that `a` must be adjacent to `d`, so it could orient `a --> b` in cases not actually implied by the pattern.
- The adjustment functions (`is_valid_adjustment`, `all_adjustment_sets`, `adjustment_set`) could reject valid adjustment sets and return a non-optimal set in several cases:
  - On an `AbstractPDAG` or `PAG`, nodes were treated as lying on a causal path from `x` to `y` when they do not (e.g. `B` in `B --- X --> Y`).
  - On an `MPDAG`, the separation step moralized the proper backdoor graph, which is only correct for CPDAGs. `is_valid_adjustment` and `all_adjustment_sets` now check amenability explicitly and block definite-status paths directly.
  - With several treatments on a `DAG`, `ADMG`, `AG` or `MAG`, a node was treated as causal when it reaches `y` only through another treatment (e.g. `W` in `X1 --> W --> X2 --> Y` with `x = [:X1, :X2]`). This affected `is_valid_adjustment`, `all_adjustment_sets`, and `adjustment_set(::DAG; type = :optimal)`.
- `backdoor_set` on a `CPDAG` could return an invalid set (e.g. `[]` for `X`, `Y` in `X --- A --> Y, X --> Y`).
- `is_valid_iv`/`all_iv_sets` accepted a confounded descendant of `x` as an instrument (e.g. `Z` in `X --> Z, X --> Y, U --> X + Y`).
- `possible_joint_parent_sets` could return joint parent sets that no DAG in the class realizes.
- `apply_background_knowledge` accepted background knowledge inconsistent with the graph (e.g. `A --> B, C --> B` on `A --- B --- C`) and returned a graph with a new v-structure. It now errors in those cases.

### Performance improvements

- Improved performance of `dag_from_pdag` by using the potential-sink worklist algorithm from Wienöbst, Bannach & Liśkiewicz (UAI 2021), instead of rescanning every remaining node after each removal.

## [0.7.0] - 2026-09-19

### Breaking changes

- `plot`'s visual defaults (colors, linewidths, etc) are no
  longer configurable via `Preferences.jl`. Instead, set a project-wide default with a Makie theme,
  e.g. `Makie.set_theme!(CausalGraphPlot = (node_color = :lightblue,))`.

- A per-edge style `Dict` (e.g. `edge_color`) no longer treats a bare node
  name as "every edge touching this node"; it now only matches a `CausalEdge`,
  a `(src, dst)` tuple, an edge-type symbol, or `:default`.

- `plot`'s node-label keywords `labels`, `label_color`, `label_fontsize`, and `label_font`
  are renamed to `node_labels`, `node_label_color`, `node_label_fontsize`, and
  `node_label_font`, for consistency with the `node_*`/`edge_*` naming used elsewhere.

- `condition_marginalize`'s keywords `cond_vars`/`marg_vars` are renamed to `given`/`index`,
  matching the `given` keyword used by `idc`/`cidp`/`prob` and the `index` argument used by
  `marginal`.

### New features

- Support of Makie themes: `plot`'s `edge_color` and `edge_label_color` now inherit the active Makie theme's
  `linecolor`/`textcolor` when not given explicitly, so e.g.
  `Makie.set_theme!(Makie.theme_dark())` keeps edges and edge labels visible against a
  dark figure.

- Automatic edge routing via dummy nodes (from Sugiyama) now work with `stretch_to_fig=true`.

- Implement idp and cidp for identifying causal effects from PAGs (Jaber et al. 2022), generalizing id/idc from ADMGs.

- `plot` gains `edge_linestyle`, styling an edge's own line (e.g. dashing `<->` edges to mark latent confounding, as is common in the literature).

- `plot` gains `edge_labels`, `edge_label_color`, `edge_label_fontsize`, `edge_label_font`,
  `edge_label_shift`, and `edge_label_distance` for drawing text along each edge, following
  its own angle.

- `uniform_dag` gains a `counts` keyword (paired with the new
  `uniform_dag_counts`) to reuse a precomputed DP table across repeated
  draws at the same `n` (or smaller).

### Performance improvements

- Improved performance of `all_frontdoor_sets`/`frontdoor_set` by reusing scratch buffers
  across recursive calls and scanning only each node's actual neighbors.
- Improved performance of `all_frontdoor_sets`/`frontdoor_set`'s step that filters out
  candidate nodes unable to satisfy the front-door criterion's third condition, by replacing
  its per-candidate reachability search with a single combined pass, for both `DAG` and `ADMG`.
- Improved performance of `all_iv_sets` by testing membership per candidate node instead
  of per combinatorial subset.
- Improved performance of `possible_joint_parent_sets`/`possible_parent_sets` by avoiding
  an expensive graph rebuild-and-validate per candidate orientation.
- Improved performance of `condition_marginalize` and `ag_to_mag` by using a single-pass
  separator-existence check instead of `minimal_separator`'s full two-pass search.

## [0.6.0] - 2026-09-14

### Breaking changes

- `plot`'s layout-algorithm keywords (e.g. `seed`, `iterations`) must now be passed as
  `layout_kwargs = (; seed = 1)` instead of directly, since `plot` is now backed by a proper
  Makie recipe with a fixed set of attributes.
- `plot` now returns a `FigureAxisPlot` instead of a `Figure`.

### New features

- Added `backdoor_set` (Generalized Backdoor Criterion) for `ADMG`.

- `CausalGraph` now supports `==` and `hash`, comparing graphs structurally (same class,
  nodes, and edges).

- `plot!(ax, cg)` draws a `CausalGraph` into an `Axis` you already own, so multiple graphs
  (or a graph and other plots) can share one `Figure`.

- `plot`/`plot!`'s returned plot is fully reactive: `plt.node_color[] = :red` restyles it
  in place, and node/label sizing keeps fitting the containing `Axis` live, including as
  it's resized.

### Bug fixes

- `is_valid_adjustment`/`all_adjustment_sets` on `ADMG` and `PAG` could wrongly validate an
  adjustment set when a node had two or more bidirected/circle edges to distinct confounders.

- `plot`'s `edge_paths` override for one edge no longer discards automatic per-edge routing
  (e.g. from `layout = :sugiyama`) for the rest of the graph's edges.

### Other changes

- Improved performance of `adjustment_set`.

## [0.5.1] - 2026-09-11

### New features

- Node-set arguments across the package (`x`/`y`/`z`, `include`/`restrict`, `latents`,
  `nodes`, etc.) now also accept a single `Symbol`, not just `Vector{Symbol}`.

### Bug fixes

- `is_valid_iv`/`all_iv_sets` on an `ADMG` could wrongly reject a valid instrument when its own edge into the treatment was bidirected (e.g. `Z <-> X`).

- `possible_parent_sets`/`possible_optimal_adjustment_sets` on an `MPDAG` only checked for a new collider at the target node, so it could wrongly accept a parent orientation that closes a directed cycle elsewhere in the graph.

- `maximal_local_mag`/`possible_local_structures`: Step 2 of the local-structure algorithm looked for a witness edge pointing out of `Vl` instead of into it.

- `meek_closure`/`is_mpdag`: R1 wrongly skipped orientations that would create a new collider, and R4 used the wrong pattern, so both could leave a background-knowledge PDAG under-oriented.

- `pagcauses`/`maximal_local_mag`: could return wrong or spurious adjustment sets. Fixed and validated testing against brute-force approach.

- `is_valid_backdoor`/`all_backdoor_sets` on a `DAG` wrongly accepted any set when `y` was itself a parent of `x`.

- The generalized adjustment criterion's forbidden set (`is_valid_adjustment`/`all_adjustment_sets` on `DAG`/`ADMG`/`AG`/`MAG`/`AbstractPDAG`/`PAG`) excluded `y` instead of `x` from the causal-path nodes before taking descendants.

### Other changes

- Package now compiles under `--trim=safe` (JuliaC).

- Improve documentation.

- `pagcauses` now parallelizes over `Threads.nthreads()` once there are enough candidates to be worth splitting across tasks.

- Improved performance of some adjustment set functions.

## [0.5.0] - 2026-09-05

### Breaking changes

- `cgraph(...; class = T)` is removed. Construct graphs by calling the graph type
  directly instead, e.g. `DAG("A --> B")`, `ADMG("A --> B, A <-> B)`.

### New features

- `plot` now supports `edge_paths`, a `Dict` overriding an edge's drawn route with an explicit polyline instead of `curvature`/automatic routing.
- Added a `:sugiyama` layout method for DAGs. Requries `using Sugiyama`,
  and if loaded is the default for DAGs.

## [0.4.0] - 2026-08-24

### Breaking changes

- `plot`'s `node_shape` `:round`/`:box` are renamed to `:circle`/`:square`.

### New features

- `plot`'s `node_shape` now supports `:ellipse`/`:rect` for label-fit stretching.
- `plot` now supports a `stretch_to_fig_size` to stretch the layout to fill `fig_size`
  instead of following the aspect of the layout.

### Bug fixes

- Fixed `plot` node sizes being shrunk by an unrelated close node pair elsewhere in the graph.
- Fixed `plot`'s automatic edge routing to use all nodes.
- Fixed `plot` clipping a curved edge at the canvas edge.
- Fixed `plot`'s `curvature` being unable to force a straight edge to override the automatic routing. `curvature` now defaults to `nothing` (auto-route) so any explicit value now works correctly.

## [0.3.1] - 2026-08-18

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
