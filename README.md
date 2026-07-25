# CausalStructures

<!---
[![Stable
Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://BjarkeHautop.github.io/CausalStructures.jl/stable)
-->
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

CausalStructures.jl provides a type-driven interface for representing,
validating, and manipulating causal graphs. Rather than treating every graph as
an arbitrary collection of nodes and edges, graph classes explicitly encode their structural assumptions and invariants.

## Graph types

The following graph types are supported:

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

Each graph class encodes structural constraints, such as no cycles,
closed under Meek’s rules, etc., and these constraints are verified on
construction.

## Quick Start

Construct graphs by specifying edges and the desired graph class:

```julia
using CausalStructures

dag = cgraph(
    directed(:U, :X),
    directed(:U, :Y),
    directed(:X, :Y);
    class = DAG,
)
```

Edges can also be written directly as a string using the same markers as above
(`+` fans a marker out to, or in from, several nodes at once):

```julia
dag = cgraph("U --> X + Y, X --> Y"; class = DAG)
```

You can then run a variety of causal graph queries, transformations,
adjustment-set computations, and separation criteria. For example, if `U` is unobserved, we can project it out to obtain an `ADMG`.

```julia
admg = latent_project(dag, [:U])
```

## Contributing

Contributions of all kinds are very welcome!

## Attribution

The package is inspired by the design principles of the R package
[caugi](https://caugi.org/). Several algorithms and tests are adapted from
caugi.
