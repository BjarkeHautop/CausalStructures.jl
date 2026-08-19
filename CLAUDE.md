# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

CausalStructures.jl is a causality-first graph package for Julia: each graph class (DAG,
CPDAG, MPDAG, ADMG, MAG, PAG, …) is its own Julia type, structurally validated on
construction, supporting causal queries, identification, and graph transformations.

All source is under `src/`, `include`d in load order from `src/load.jl` (itself `include`d
by `src/CausalStructures.jl`, which holds the export list). Tests live in `test/`.

## Development commands

- **Test**: `julia --project=. -e "using Pkg; Pkg.test()"` (or `julia --project=test test/runtests.jl`)
- **REPL with the project active**: `julia --project=.`
- **Format**: `pre-commit run julia-formatter --all-files` (or `pre-commit run --all-files` for every hook)
- **Build docs**: `julia --project=docs docs/make.jl`

### Testing via julia-mcp

When the [julia-mcp](https://github.com/aplavin/julia-mcp) server is available,
prefer it over spawning new Julia processes — the session stays alive between
calls, avoiding recompilation. Use `<full path>/test` as `env_path`, load the
runner once with `using TestItemRunner`, then run filtered tests:

- All tests: `@run_package_tests verbose=false`
- By test name: `@run_package_tests verbose=false filter=ti->contains(ti.name, "some name")`
- By filename: `@run_package_tests verbose=false filter=ti->contains(ti.filename, "some-file")`

Tests are `@testitem`s tagged `:unit`; each test file is self-contained and imports
`CausalStructures` directly. Shared fixtures live in `test/helper-dag.jl` and
`test/helper-mag-to-pag.jl`; `test/Aqua.jl` runs package-quality checks (Aqua.jl).

## Conventions

- Breaking changes are allowed — never consider backwards compatibility.
- All arrows in comments must use ASCII (e.g. `-->`, `<--`), not Unicode.
- File names use kebab-case.
- Don't use `@inline` — relying on the Julia compiler is better.
- Match the existing code style in `src/`.
- Add or update tests in `test/` for any behavior change.
- Keep public API changes documented — exports live in `src/CausalStructures.jl`.
- Code is formatted with [JuliaFormatter](https://github.com/domluna/JuliaFormatter.jl) per
  `.JuliaFormatter.toml` (4-space indent, 92-col margin). `pre-commit run --all-files` also
  runs markdownlint, yamllint, trailing-whitespace, and CFF validation.
- Never commit changes — the user handles all commits.

## Architecture

### Graph class hierarchy and construction

```text
CausalGraph
├── DAG
├── UG
├── AbstractPDAG
│   ├── PDAG
│   ├── CPDAG
│   └── MPDAG
├── ADMG
├── AbstractAG
│   ├── AG
│   └── MAG
├── PAG
└── UNKNOWN
```

`src/core/` defines this hierarchy and is the load-order-sensitive foundation everything
else builds on: `defs.jl` (types, backend structs), `edges.jl` (`directed`, `undirected`,
`bidirected`, `partially_directed`, `partially_undirected`, `partial`), `constructors.jl`
(`cgraph(...)` front door, dispatching through `build_graph` -> type constructor ->
`_build_graph` -> `build_backend` + `validate`), `graph-string.jl` (the `cgraph(::String)`
DSL parser, e.g. `"A --> B + C"`), `mutate.jl` (`add_edge`/`remove_edge`/`add_node`/
`remove_node`/`reclass`), and `validate.jl` (`is_dag`, `is_mpdag`, `is_mag`, `is_pag`, …,
plus the `validate` dispatch every constructor calls). Each graph class has its own backend
struct (`DAGBackend`, `ADMGBackend`, `AGBackend`, …) built in `backend.jl` using a packed
CSR layout: one `rowval` vector holds all neighbors contiguously, `colptr` gives each
node's slice, and `deg[bucket, node]` records the width of each relationship bucket
(parents/children/spouses/undirected).

### `src/query/` — traversal and separation

`traversal.jl` covers the basics (`ancestors`, `descendants`, `parents`, `children`,
`spouses`, `neighbors`, `topological_sort`, `markov_blanket`, `districts`, …);
`separation.jl` adds `d_separated`/`m_separated`; `minimal-separator.jl` and
`possible-d-sep.jl` (Definite/Possible-D-SEP, for MAGs/PAGs) build on those to support the
identification layer above.

### `src/identification/` — adjustment, backdoor, frontdoor, IV, and `id`

Each classical criterion is implemented once per applicable graph class, sharing a common
shape across files: `adjustment-{admg,mag,pag,pdag}.jl` are the generalized adjustment
criterion (GAC) per class (`is_valid_adjustment`, `all_adjustment_sets`), and
`backdoor.jl`/`backdoor-{pdag,mag,pag}.jl` are the generalized backdoor criterion (GBC) per
class. `enumerate-subsets.jl` is the shared brute-force subset search all the `all_*_sets`
functions bottom out in. `frontdoor.jl` and `iv.jl` (Brito & Pearl 2002) are independent
criteria. `id.jl` implements the Shpitser & Pearl (2008) `id`/`idc` algorithm for ADMGs,
producing `Estimand` expression trees (`Prob`/`Marginal`/`Product`/`Quotient`, defined in
`estimand.jl`). `possible-adjustment-sets.jl` and `possible-joint-parent-sets.jl` compute
adjustment sets over MPDAGs under partial background knowledge; `pagcauses.jl` (Wang, Tao,
Qin & Zhou 2025) generalizes this to PAGs by combining across every locally-consistent MAG,
using `transform/local-structure.jl`.

### `src/transform/` — graph-to-graph transformations

`skeleton-subgraph.jl` (`skeleton`, `subgraph`, `moralize`) and `latent.jl`
(`latent_project`, `exogenize`, `normalize_latent_structure`) are self-contained. `pdag.jl`
(`dag_from_pdag`, `dag_to_cpdag`, `dag_to_mpdag`, `meek_closure`) and
`background-knowledge.jl` (`BackgroundKnowledge`/`RequiredEdge`/`ForbiddenEdge`,
`apply_background_knowledge`, per Meek 1995) work together to orient PDAGs under
constraints. `mag.jl` implements the MAG<->PAG equivalence-class transform (Zhang 2008):
`mag_to_pag`, `mag_from_pag`, `ag_to_mag`. `local-structure.jl` (Wang, Qin & Zhou 2023) and
`enumerate-mags.jl` both enumerate MAGs consistent with a PAG — the former per-vertex
(`possible_local_structures`, `maximal_local_mag`, feeding `pagcauses.jl`), the latter
globally (`enumerate_mags`). `enumerate-dags.jl` (`enumerate_dags`, `count_dags`) is the DAG
analogue.

### `src/io/` — generation, simulation, display, layout

`utils.jl` (`generate_graph`, `simulate_data`, printing) and `uniform-dag.jl`
(`uniform_dag`, exact uniform random DAG sampling per Kuipers & Moffa 2015) are
self-contained generators. `layout.jl` is a stub that delegates to the optional `MakieExt`
extension (`ext/`, plotting via Makie + NetworkLayout; `NetworkLayoutExt` is the layout-only
counterpart for when Makie isn't loaded).

### Algorithm references

Several files implement one specific published algorithm named in a comment at the top of
the file — e.g. `id.jl` -> Shpitser & Pearl 2008, `iv.jl` -> Brito & Pearl 2002, `mag.jl` ->
Zhang 2008, `pagcauses.jl` -> Wang, Tao, Qin & Zhou 2025, `local-structure.jl` -> Wang, Qin
& Zhou 2023, `uniform-dag.jl` -> Kuipers & Moffa 2015, `adjustment-pag.jl` (GAC) ->
Perković, Textor, Kalisch & Maathuis 2018. PDF copies of several of these papers are kept at
the repo root for reference.
