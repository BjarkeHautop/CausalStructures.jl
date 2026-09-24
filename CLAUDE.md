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

- All arrows in comments must use ASCII (e.g. `-->`, `<--`), not Unicode.
- File names use kebab-case.
- Don't use `@inline` — relying on the Julia compiler is better.
- Match the existing code style in `src/`.
- Add or update tests in `test/` for any behavior change.
- Keep public API changes documented — exports live in `src/CausalStructures.jl`.
- Code is formatted with [JuliaFormatter](https://github.com/domluna/JuliaFormatter.jl) per
  `.JuliaFormatter.toml` (4-space indent, 92-col margin). `prek run --all-files` also
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
else builds on: type/backend definitions, edge-kind predicates, per-class constructors
(each graph type is its own constructor, e.g. `DAG(...)` and the string-DSL form
`DAG("A --> B + C")`), node/edge editing, and the structural validation every constructor
runs on construction. Each graph class has its own backend struct using a packed CSR
layout for its adjacency data.

### `src/query/` — traversal and separation

Basic traversal (ancestors, descendants, parents, children, spouses, neighbors,
topological sort, Markov blanket, districts, …), d-separation/m-separation, and the
Definite/Possible-D-SEP routines (for MAGs/PAGs) that the identification layer above
builds on.

### `src/identification/` — adjustment, backdoor, frontdoor, IV, and `id`

Each classical criterion is implemented once per applicable graph class: the generalized
adjustment criterion (GAC) and the generalized backdoor criterion (GBC), both per graph
class. `frontdoor.jl` and `iv.jl` (Brito & Pearl 2002) are independent criteria. `id.jl`
implements the Shpitser & Pearl (2008) `id`/`idc` algorithm for ADMGs. Separately,
`possible-adjustment-sets.jl`/`possible-joint-parent-sets.jl` compute adjustment sets over
MPDAGs under partial background knowledge, and `pagcauses.jl` (Wang, Tao, Qin & Zhou 2025)
generalizes this to PAGs by combining across every locally-consistent MAG.

### `src/transform/` — graph-to-graph transformations

Skeleton/subgraph/moralization and latent-projection utilities are self-contained.
DAG<->CPDAG/MPDAG conversion and Meek-closure orientation work together with background-
knowledge application (required/forbidden edges, per Meek 1995) to orient PDAGs under
constraints. `mag.jl` implements the MAG<->PAG equivalence-class transform (Zhang 2008).
`local-structure.jl` (Wang, Qin & Zhou 2023) and `enumerate-mags.jl` both enumerate MAGs
consistent with a PAG — the former per-vertex, the latter globally — and
`enumerate-dags.jl` is the DAG analogue.

### `src/io/` — generation, simulation, display, layout

Graph generation, data simulation, printing, and exact uniform random DAG sampling
(Kuipers & Moffa 2015) are self-contained. `layout.jl` delegates to the optional `MakieExt`
extension (`ext/`, plotting via Makie + NetworkLayout; `NetworkLayoutExt` is the
layout-only counterpart for when Makie isn't loaded).

### `src/metrics/` — graph comparison

`hamming.jl` (`hd`, `shd`) compares edges only, across any graph classes.
`separation-distance.jl` (`separation_distance`, Wahl & Runge 2025) compares
implied separations via a class-specific strategy; not symmetric by default.
`sc-metric.jl` (`sc_metric`, `markov_metric`, `faithfulness_metric`) checks
every separation/connection statement up to a conditioning-set order: the
most complete and most expensive comparison. Both require the two graphs to
share one separation notion.

### Algorithm references

Several files implement one specific published algorithm named in a comment at the top of
the file (Shpitser & Pearl 2008, Brito & Pearl 2002, Zhang 2008, Wang/Tao/Qin/Zhou 2025,
Wang/Qin/Zhou 2023, Kuipers & Moffa 2015, Perković/Textor/Kalisch/Maathuis 2018, …) — check
that comment for the reference rather than relying on this list. PDF copies of several of
these papers are kept at the repo root for reference.
