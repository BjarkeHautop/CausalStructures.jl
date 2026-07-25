# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Key Rules (from AGENTS.md)

- Breaking changes are allowed — never consider backwards compatibility.
- All arrows in comments must use ASCII (e.g. `-->`, `<--`), not Unicode.
- File names use kebab-case.
- Don't use `@inline` - relying on Julia compiler is better.

## Commands

**Run all tests:**

```bash
julia --project=test test/runtests.jl
```

This runs the complete test suite and outputs a summary at the end.

## Git workflow

Never commit changes. The user will handle all commits.

**Format code** (JuliaFormatter, 4-space indent, 92-char margin):

```bash
pre-commit run julia-formatter --all-files
```

**Run all pre-commit hooks:**

```bash
pre-commit run --all-files
```

**Build docs:**

```bash
julia --project=docs docs/make.jl
```

## Architecture

Source is organized under `src/core.jl` (the loader) into five subdirectories:

### `src/core/` — Foundation (load-order sensitive)

| File | Purpose |
|------|---------|
| `defs.jl` | Core type definitions: `CausalEdge`, `CausalGraph` hierarchy, backend structs, concrete graph types |
| `edges.jl` | Edge constructor functions (`directed`, `undirected`, `bidirected`, `partially_directed`, `partially_undirected`, `partial`) |
| `constructors.jl` | `cgraph(...)` front door, `node(...)`, `build_graph` dispatch |
| `graph-string.jl` | `cgraph(::AbstractString)` string-DSL parser (e.g. `"A --> B + C"`) |
| `mutate.jl` | `add_edge`, `remove_edge`, `add_node`, `remove_node`, `reclass` |
| `validate.jl` | `is_dag`, `is_cpdag`, `is_mpdag`, `is_admg`, `is_ag`, `is_mag`, … and `validate` dispatch used by constructors |
| `backend.jl` | Packed-CSR backend construction per graph class |

### `src/query/` — Graph query algorithms

| File | Purpose |
|------|---------|
| `traversal.jl` | `ancestors`, `descendants`, `parents`, `children`, `spouses`, `neighbors`, `topological_sort`, `markov_blanket`, … |
| `separation.jl` | `d_separated`, `m_separated` |
| `minimal-separator.jl` | `minimal_separator` |

### `src/identification/` — Causal identification

| File | Purpose |
|------|---------|
| `adjustment-admg.jl` | Generalized adjustment criterion for ADMG: `is_valid_adjustment`, `all_adjustment_sets` |
| `adjustment-mag.jl` | Generalized adjustment criterion for MAG: `is_valid_adjustment`, `all_adjustment_sets` |
| `adjustment-pdag.jl` | Generalized adjustment criterion for PDAG/CPDAG/MPDAG: `is_valid_adjustment`, `all_adjustment_sets` |
| `backdoor.jl` | `is_valid_backdoor`, `all_backdoor_sets`, `adjustment_set` |
| `frontdoor.jl` | `is_valid_frontdoor`, `frontdoor_set`, `all_frontdoor_sets` |
| `condition-marginalize.jl` | `condition_marginalize` |

### `src/transform/` — Graph-to-graph transformations

| File | Purpose |
|------|---------|
| `skeleton-subgraph.jl` | `skeleton`, `subgraph`, `moralize` |
| `latent.jl` | `latent_project`, `exogenize`, `normalize_latent_structure` |
| `pdag.jl` | `dag_from_pdag`, `dag_to_cpdag`, `meek_closure` |
| `enumerate-dags.jl` | `enumerate_dags`, `count_dags` |

### `src/io/` — I/O, generation, display

| File | Purpose |
|------|---------|
| `utils.jl` | `generate_graph`, `simulate_data`, printing |
| `uniform-dag.jl` | `uniform_dag` — exact uniform random DAG sampling (Kuipers & Moffa, 2015) |
| `layout.jl` | `layout` (stub; delegates to `MakieExt`) |

Optional extensions in `ext/`: `MakieExt` (plotting via Makie + NetworkLayout), `NetworkLayoutExt`.

### Backend storage

Each graph class has a dedicated backend struct (e.g. `DAGBackend`, `ADMGBackend`) using a packed CSR layout: a single `rowval` vector holds all neighbors contiguously, `colptr` gives each node's slice, and `deg[bucket, node]` records the width of each relationship bucket (parents/children/spouses/undirected).

### Graph class hierarchy

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
└── UNKNOWN
```

Graphs are validated on construction via `validate(cg, T)` in `core/validate.jl`. Construction always goes through `cgraph(...)` → `build_graph` → type constructor → `_build_graph` → `build_backend` + `validate`.

### Tests

Tests use `TestItemRunner` with `@testitem` blocks (not `@testset`). Each test file is self-contained and imports `CausalStructures` directly. Tags used: `[:unit]`.
