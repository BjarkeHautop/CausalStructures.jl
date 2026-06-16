# CausalGraphInterface

[![Stable
Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://BjarkeHautop.github.io/CausalGraphInterface.jl/stable)
[![Development
documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://BjarkeHautop.github.io/CausalGraphInterface.jl/dev)
[![Test workflow
status](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/BjarkeHautop/CausalGraphInterface.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/BjarkeHautop/CausalGraphInterface.jl)
[![Lint workflow
Status](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Lint.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Lint.yml?query=branch%3Amain)
[![Docs workflow
Status](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/BjarkeHautop/CausalGraphInterface.jl/actions/workflows/Docs.yml?query=branch%3Amain)
[![BestieTemplate](https://img.shields.io/endpoint?url=https://raw.githubusercontent.com/JuliaBesties/BestieTemplate.jl/main/docs/src/assets/badge.json)](https://github.com/JuliaBesties/BestieTemplate.jl)

CausalGraphInterface.jl provides a type-driven interface for representing,
validating, and manipulating causal graphs. Rather than treating every graph as
an arbitrary collection of nodes and edges, graph classes explicitly encode
their structural assumptions and invariants.

The package is inspired by the design principles of the R package
[caugi](https://caugi.org/) and aims to provide a similarly expressive and
extensible foundation for causal graphs in Julia.

## Design Philosophy

Different causal graph classes represent different assumptions, both on the
allowed edge types and on the graph structure itself. For example, a DAG must be
acyclic, while a CPDAG must satisfy additional equivalence-class constraints.
Graphs are validated during construction, ensuring that every graph instance
satisfies the invariants of its class.

## Supported Graph Classes

Currently implemented:

- Directed Acyclic Graphs (`DAG`)
- Undirected Graphs (`UG`)
- Partially Directed Acyclic Graphs (`PDAG`)
- Completed Partially Directed Acyclic Graphs (`CPDAG`)
- Maximally Oriented Partially Directed Acyclic Graphs (`MPDAG`)
- Acyclic Directed Mixed Graphs (`ADMG`)
- Ancestral Graphs (`AG`)
- Maximal Ancestral Graphs (`MAG`)
- Partial Ancestral Graphs (`PAG`)
- Arbitrary graphs (`UNKNOWN`)

`UNKNOWN` can be used for currently unsupported graph classes.

The following edge types exists:

- `directed(:A, :B)` for `A --> B`
- `undirected(:A, :B)` for `A --- B`
- `bidirected(:A, :B)` for `A <-> B`
- `partially_directed(:A, :B)` for `A o-> B`
- `partially_undirected(:A, :B)` for `A o-- B`
- `partial(:A, :B)` for `A o-o B`

## Quick Start

Construct graphs by specifying edges and the desired graph class:

```julia
using CausalGraphInterface

dag = caugi(
    directed(:U, :X),
    directed(:U, :Y),
    directed(:X, :Y);
    class = DAG,
)
```

You can then run a variety of causal graph queries, transformations,
adjustment-set computations, and separation criteria. For example, if `U` is
unobserved, we can project it out to obtain an `ADMG`.

```julia
admg = latent_project(dag, [:U])
```

## To Do

Figure out a better syntax than using `directed(), undirected()`, etc. Ideally,
we would support edge operators similar to the syntax used in R. I.e. in R you
can do

```r
A %o->% B
```

for a parially directed edge.

Maybe use `Edge(..., directed)` instead of `directed(...)`, and similar for the
rest?

Allow one of the arguments to be a vector (but not both at the same time)? I.e.
`directed([:U, :Y], :X)` to mean `directed(:U, :X)` and `directed(:Y, :X)`?
