# CausalStructures

[![Stable
Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://BjarkeHautop.github.io/CausalStructures.jl/stable)
[![Development
documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://BjarkeHautop.github.io/CausalStructures.jl/dev)
[![Test workflow
status](https://github.com/BjarkeHautop/CausalStructures.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalStructures.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/BjarkeHautop/CausalStructures.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/BjarkeHautop/CausalStructures.jl)
[![Lint workflow
Status](https://github.com/BjarkeHautop/CausalStructures.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalStructures.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow
Status](https://github.com/BjarkeHautop/CausalStructures.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalStructures.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)
[![Aqua QA](https://juliatesting.github.io/Aqua.jl/dev/assets/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

CausalStructures.jl is a Julia package for causal graphs and causal
inference. It provides graph representations for the structures used in
causal inference, along with algorithms for graphical queries, causal
identification, and transformations between graph classes.

## Installation

CausalStructures can be installed directly from the Julia package manager.
In the Julia REPL, press `]` to enter the Pkg mode, then run:

```julia
pkg> add CausalStructures
```

## Quick Start

Construct graphs by specifying edges and the desired graph class. The
quickest way is to write edges directly as a string, using markers such as
`-->` for directed edges (`+` fans a marker out to, or in from, several
nodes at once); edges can equivalently be built up from constructor calls
like `directed(:A, :B)`, which is useful when composing them programmatically.

```julia
using CausalStructures

dag = DAG("C --> X, A --> X + K, X --> F + D, K --> Y, D --> Y + G, Y --> H")
```

`adjustment_set` finds a set of variables that identifies the causal effect
of `X` on `Y`, here via the O-set, which minimizes the asymptotic variance
of the effect estimator:

```julia
adjustment_set(dag, :X, :Y; type = :optimal)
#> 1-element Vector{Symbol}:
#>  :K
```

If `K` is unobserved, we can project it out to obtain an ADMG over the observed variables. We can then enumerate all valid adjustment sets under the generalized adjustment criterion:

```julia
admg = latent_project(dag, :K)
all_adjustment_sets(admg, :X, :Y)
```

See the [Getting Started guide](https://bjarkehautop.github.io/CausalStructures.jl/stable/05-quick-guide/)
for a full walkthrough, and the [Causal Identification guide](https://bjarkehautop.github.io/CausalStructures.jl/stable/20-causal-identification/)
for frontdoor adjustment, instrumental variables, and minimal separators.

## Graph classes

Each causal graph class is its own type, structurally validated on
construction:

    CausalGraph
    ├─ DAG            Directed Acyclic Graph
    ├─ UG             Undirected Graph
    ├─ AbstractPDAG   All Partially Directed Acyclic Graphs
    │  ├─ PDAG        Partially Directed Acyclic Graph
    │  ├─ CPDAG       Completed Partially Directed Acyclic Graph
    │  └─ MPDAG       Maximally Oriented Partially Directed Acyclic Graph
    ├─ ADMG           Acyclic Directed Mixed Graph
    ├─ AbstractAG     All Ancestral Graphs
    │  ├─ AG          Ancestral Graph
    │  └─ MAG         Maximal Ancestral Graph
    ├─ PAG            Partial Ancestral Graph
    └─ UNKNOWN        No structural constraints

The package provides methods to work with these graphs:

- Queries such as parents, ancestors, and m-separation;
- Operations such as moralize, meek closure, and conversion to/from equivalence classes;
- Causal identification such as the Generalized Adjustment Criterion, backdoor, frontdoor, and instrumental variables;
- Random graph generation and data simulation;
- Visualization of any graph class via Makie.

## Performance

Built with performance in mind: queries and identification algorithms stay fast even on graphs
with thousands of nodes. See the
[Benchmarks guide](https://bjarkehautop.github.io/CausalStructures.jl/stable/70-benchmarks/)
for details, and [benchmark/](https://github.com/BjarkeHautop/CausalStructures.jl/tree/main/benchmark)
for comparisons with [CausalInference.jl](https://github.com/mschauer/CausalInference.jl).

## Contributing

Contributions of all kinds are very welcome!

## Attribution

The package is inspired by the design principles of the R package
[caugi](https://caugi.org/). Several algorithms and tests are adapted from caugi.
